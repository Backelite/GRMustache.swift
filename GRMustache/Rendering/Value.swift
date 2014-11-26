//
//  Value.swift
//  GRMustache
//
//  Created by Gwendal Roué on 08/11/2014.
//  Copyright (c) 2014 Gwendal Roué. All rights reserved.
//


// =============================================================================
// MARK: - Facet Protocols

public protocol MustacheWrappable {
}

public protocol MustacheCluster: MustacheWrappable {
    
    /**
    Controls whether the object should trigger or avoid the rendering
    of Mustache sections.
    
    - true: `{{#object}}...{{/}}` are rendered, `{{^object}}...{{/}}`
    are not.
    - false: `{{^object}}...{{/}}` are rendered, `{{#object}}...{{/}}`
    are not.
    
    Example:
    
    class MyObject: MustacheCluster {
    let mustacheBool = true
    }
    
    :returns: Whether the object should trigger the rendering of
    Mustache sections.
    */
    var mustacheBool: Bool { get }
    
    /**
    TODO
    */
    var mustacheInspectable: MustacheInspectable? { get }
    
    /**
    Controls whether the object can be used as a filter.
    
    :returns: An optional filter object that should be applied when the object
    is involved in a filter expression such as `object(...)`.
    */
    var mustacheFilter: MustacheFilter? { get }
    
    /**
    TODO
    */
    var mustacheTagObserver: MustacheTagObserver? { get }
    
    /**
    TODO
    */
    var mustacheRenderable: MustacheRenderable? { get }
}

public protocol MustacheFilter: MustacheWrappable {
    func mustacheFilterByApplyingArgument(argument: Value) -> MustacheFilter?
    func transformedMustacheValue(value: Value, error: NSErrorPointer) -> Value?
}

public protocol MustacheInspectable: MustacheWrappable {
    func valueForMustacheKey(key: String) -> Value?
}

public protocol MustacheRenderable: MustacheWrappable {
    func mustacheRender(info: RenderingInfo, error: NSErrorPointer) -> Rendering?
}

public protocol MustacheTagObserver: MustacheWrappable {
    func mustacheTag(tag: Tag, willRenderValue value: Value) -> Value
    
    // If rendering is nil then an error has occurred.
    func mustacheTag(tag: Tag, didRender rendering: String?, forValue value: Value)
}


// =============================================================================
// MARK: - Value

public class Value {
    private enum Type {
        case None
        case AnyObjectValue(AnyObject)
        case DictionaryValue([String: Value])
        case ArrayValue([Value])
        case SetValue(NSSet)
        case ClusterValue(MustacheCluster)
    }
    
    private let type: Type
    
    public var isEmpty: Bool {
        switch type {
        case .None:
            return true
        default:
            return false
        }
    }
    
    private init(type: Type) {
        self.type = type
    }
    
    public convenience init() {
        self.init(type: .None)
    }
    
    // TODO: find a way to prevent the Value(Value) construct
    public convenience init!(_ value: Value) {
        self.init(type: value.type)
    }
    
    public convenience init(_ object: AnyObject?) {
        if let object: AnyObject = object {
            if object is NSNull {
                self.init()
            } else if let number = object as? NSNumber {
                let objCType = number.objCType
                let str = String.fromCString(objCType)
                switch str! {
                case "c", "i", "s", "l", "q", "C", "I", "S", "L", "Q":
                    self.init(Int(number.longLongValue))
                case "f", "d":
                    self.init(number.doubleValue)
                case "B":
                    self.init(number.boolValue)
                default:
                    fatalError("Not implemented yet")
                }
            } else if let string = object as? NSString {
                self.init(string as String)
            } else if let dictionary = object as? NSDictionary {
                var canonicalDictionary: [String: Value] = [:]
                dictionary.enumerateKeysAndObjectsUsingBlock({ (key, value, _) -> Void in
                    canonicalDictionary["\(key)"] = Value(value)
                })
                self.init(canonicalDictionary)
            } else if let enumerable = object as? NSFastEnumeration {
                if let enumerableObject = object as? NSObjectProtocol {
                    if enumerableObject.respondsToSelector("objectAtIndexedSubscript:") {
                        // Array
                        var array: [Value] = []
                        let generator = NSFastGenerator(enumerable)
                        while true {
                            if let item: AnyObject = generator.next() {
                                array.append(Value(item))
                            } else {
                                break
                            }
                        }
                        self.init(array)
                    } else {
                        // Set
                        var set = NSMutableSet()
                        let generator = NSFastGenerator(enumerable)
                        while true {
                            if let item: AnyObject = generator.next() {
                                set.addObject(item)
                            } else {
                                break
                            }
                        }
                        self.init(type: .SetValue(set))
                    }
                } else {
                    // Assume Array
                    var array: [Value] = []
                    let generator = NSFastGenerator(enumerable)
                    while true {
                        if let item: AnyObject = generator.next() {
                            array.append(Value(item))
                        } else {
                            break
                        }
                    }
                    self.init(array)
                }
            } else {
                self.init(type: .AnyObjectValue(object))
            }
        } else {
            self.init()
        }
    }
    
    public convenience init(_ dictionary: [String: Value]) {
        self.init(type: .DictionaryValue(dictionary))
    }
    
    public convenience init(_ array: [Value]) {
        self.init(type: .ArrayValue(array))
    }

    private class func wrappableFromCluster(cluster: MustacheCluster?) -> MustacheWrappable? {
        return cluster?.mustacheFilter ?? cluster?.mustacheInspectable ?? cluster?.mustacheRenderable ?? cluster?.mustacheTagObserver ?? cluster
    }
    
}


// =============================================================================
// MARK: - Dictionary Convenience Initializers

extension Value {
    
    public convenience init(_ dictionary: [String: AnyObject]) {
        var mustacheDictionary: [String: Value] = [:]
        for (key, value) in dictionary {
            mustacheDictionary[key] = Value(value)
        }
        self.init(mustacheDictionary)
    }
}


// =============================================================================
// MARK: - MustacheFilter Convenience Initializers

extension Value {
    
    public convenience init(_ block: (Value, NSErrorPointer) -> Value?) {
        self.init(BlockFilter(block: block))
    }
    
    public convenience init(_ block: (Value) -> Value?) {
        self.init(BlockFilter(block: { (value: Value, error: NSErrorPointer) -> Value? in
            return block(value)
        }))
    }
    
    public convenience init(_ block: ([Value], NSErrorPointer) -> Value?) {
        self.init(BlockVariadicFilter(arguments: [], block: block))
    }
    
    public convenience init(_ block: ([Value]) -> Value?) {
        self.init(BlockVariadicFilter(arguments: [], block: { (arguments: [Value], error: NSErrorPointer) -> Value? in
            return block(arguments)
        }))
    }
    
    public convenience init(_ block: (AnyObject?) -> Value?) {
        self.init(BlockFilter(block: { (value: Value, error: NSErrorPointer) -> Value? in
            if let object:AnyObject = value.object() {
                return block(object)
            } else {
                return block(nil)
            }
        }))
    }
    
    public convenience init<T: MustacheWrappable>(_ block: (T?) -> Value?) {
        self.init(BlockFilter(block: { (value: Value, error: NSErrorPointer) -> Value? in
            if let object:T = value.object() {
                return block(object)
            } else {
                return block(nil)
            }
        }))
    }
    
    public convenience init<T: NSObjectProtocol>(_ block: (T?) -> Value?) {
        self.init(BlockFilter(block: { (value: Value, error: NSErrorPointer) -> Value? in
            if let object:T = value.object() {
                return block(object)
            } else {
                return block(nil)
            }
        }))
    }
    
    public convenience init(_ block: (Int?) -> Value?) {
        self.init(BlockFilter(block: { (value: Value, error: NSErrorPointer) -> Value? in
            if let int = value.toInt() {
                return block(int)
            } else {
                return block(nil)
            }
        }))
    }
    
    public convenience init(_ block: (Double?) -> Value?) {
        self.init(BlockFilter(block: { (value: Value, error: NSErrorPointer) -> Value? in
            if let double = value.toDouble() {
                return block(double)
            } else {
                return block(nil)
            }
        }))
    }
    
    public convenience init(_ block: (String?) -> Value?) {
        self.init(BlockFilter(block: { (value: Value, error: NSErrorPointer) -> Value? in
            if let string = value.toString() {
                return block(string)
            } else {
                return block(nil)
            }
        }))
    }
    
    private struct BlockFilter: MustacheFilter {
        let block: (Value, NSErrorPointer) -> Value?
        
        func mustacheFilterByApplyingArgument(argument: Value) -> MustacheFilter? {
            return nil
        }
        
        func transformedMustacheValue(value: Value, error: NSErrorPointer) -> Value? {
            return block(value, error)
        }
    }
    
    private struct BlockVariadicFilter: MustacheFilter {
        let arguments: [Value]
        let block: ([Value], NSErrorPointer) -> Value?
        
        func mustacheFilterByApplyingArgument(argument: Value) -> MustacheFilter? {
            return BlockVariadicFilter(arguments: arguments + [argument], block: block)
        }
        
        func transformedMustacheValue(value: Value, error: NSErrorPointer) -> Value? {
            return block(arguments + [value], error)
        }
    }
}




// =============================================================================
// MARK: - MustacheFilter + MustacheRenderable Convenience Initializers

extension Value {
    
    public convenience init(_ block: (Value, info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (value: Value) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(value, info: info, error: error)
            })
        })
    }
    
    public convenience init(_ block: ([Value], info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (arguments: [Value]) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(arguments, info: info, error: error)
            })
        })
    }
    
    public convenience init(_ block: (AnyObject?, info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (object: AnyObject?) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(object, info: info, error: error)
            })
        })
    }
    
    public convenience init<T: MustacheWrappable>(_ block: (T?, info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (object: T?) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(object, info: info, error: error)
            })
        })
    }
    
    public convenience init<T: NSObjectProtocol>(_ block: (T?, info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (object: T?) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(object, info: info, error: error)
            })
        })
    }
    
    public convenience init(_ block: (Int?, info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (int: Int?) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(int, info: info, error: error)
            })
        })
    }
    
    public convenience init(_ block: (Double?, info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (double: Double?) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(double, info: info, error: error)
            })
        })
    }
    
    public convenience init(_ block: (String?, info: RenderingInfo, error: NSErrorPointer) -> Rendering?) {
        self.init( { (string: String?) -> Value in
            return Value( { (info: RenderingInfo, error: NSErrorPointer) -> Rendering? in
                return block(string, info: info, error: error)
            })
        })
    }
}


// =============================================================================
// MARK: - MustacheRenderable Convenience Initializers

extension Value {
    
    public convenience init(_ block: (RenderingInfo, NSErrorPointer) -> Rendering?) {
        self.init(BlockRenderable(block: block))
    }
    
    private struct BlockRenderable: MustacheRenderable {
        let block: (RenderingInfo, NSErrorPointer) -> Rendering?
        
        func mustacheRender(info: RenderingInfo, error: NSErrorPointer) -> Rendering? {
            return block(info, error)
        }
    }
}


// =============================================================================
// MARK: - MustacheCluster Convenience Initializers

extension Value {
    
    public convenience init(_ object: protocol<MustacheCluster>) { self.init(type: .ClusterValue(object)) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter, MustacheInspectable>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter, MustacheInspectable, MustacheRenderable>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter, MustacheInspectable, MustacheRenderable, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter, MustacheInspectable, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter, MustacheRenderable>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter, MustacheRenderable, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheFilter, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheInspectable>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheInspectable, MustacheRenderable>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheInspectable, MustacheRenderable, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheInspectable, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheRenderable>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheRenderable, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheCluster, MustacheTagObserver>) { self.init(object as MustacheCluster) }
    public convenience init(_ object: protocol<MustacheFilter>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheFilter, MustacheInspectable>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheFilter, MustacheInspectable, MustacheRenderable>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheFilter, MustacheInspectable, MustacheRenderable, MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheFilter, MustacheInspectable, MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheFilter, MustacheRenderable>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheFilter, MustacheRenderable, MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheFilter, MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheInspectable>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheInspectable, MustacheRenderable>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheInspectable, MustacheRenderable, MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheInspectable, MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheRenderable>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheRenderable, MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    public convenience init(_ object: protocol<MustacheTagObserver>) { self.init(ClusterWrapper(object)) }
    
    private struct ClusterWrapper: MustacheCluster, DebugPrintable {
        let mustacheBool = true
        let mustacheFilter: MustacheFilter?
        let mustacheInspectable: MustacheInspectable?
        let mustacheRenderable: MustacheRenderable?
        let mustacheTagObserver: MustacheTagObserver?

        init(_ object: protocol<MustacheFilter>) { mustacheFilter = object }
        init(_ object: protocol<MustacheFilter, MustacheInspectable>) { mustacheFilter = object; mustacheInspectable = object }
        init(_ object: protocol<MustacheFilter, MustacheInspectable, MustacheRenderable>) { mustacheFilter = object; mustacheInspectable = object; mustacheRenderable = object }
        init(_ object: protocol<MustacheFilter, MustacheInspectable, MustacheRenderable, MustacheTagObserver>) { mustacheFilter = object; mustacheInspectable = object; mustacheRenderable = object; mustacheTagObserver = object }
        init(_ object: protocol<MustacheFilter, MustacheInspectable, MustacheTagObserver>) { mustacheFilter = object; mustacheInspectable = object; mustacheTagObserver = object }
        init(_ object: protocol<MustacheFilter, MustacheRenderable>) { mustacheFilter = object; mustacheRenderable = object }
        init(_ object: protocol<MustacheFilter, MustacheRenderable, MustacheTagObserver>) { mustacheFilter = object; mustacheRenderable = object; mustacheTagObserver = object }
        init(_ object: protocol<MustacheFilter, MustacheTagObserver>) { mustacheFilter = object; mustacheTagObserver = object }
        init(_ object: protocol<MustacheInspectable>) { mustacheInspectable = object }
        init(_ object: protocol<MustacheInspectable, MustacheRenderable>) { mustacheInspectable = object; mustacheRenderable = object }
        init(_ object: protocol<MustacheInspectable, MustacheRenderable, MustacheTagObserver>) { mustacheInspectable = object; mustacheRenderable = object; mustacheTagObserver = object }
        init(_ object: protocol<MustacheInspectable, MustacheTagObserver>) { mustacheInspectable = object; mustacheTagObserver = object }
        init(_ object: protocol<MustacheRenderable>) { mustacheRenderable = object }
        init(_ object: protocol<MustacheRenderable, MustacheTagObserver>) { mustacheRenderable = object; mustacheTagObserver = object }
        init(_ object: protocol<MustacheTagObserver>) { mustacheTagObserver = object }
        
        var debugDescription: String {
            let object: Any = mustacheFilter ?? mustacheRenderable ?? mustacheTagObserver ?? mustacheInspectable ?? "null"
            return "ClusterWrapper(\(object))"
        }
    }
}


// =============================================================================
// MARK: - Value unwrapping

extension Value {
    
    public func object() -> AnyObject? {
        switch type {
        case .AnyObjectValue(let object):
            return object
        case .DictionaryValue(let dictionary):
            var result = NSMutableDictionary()
            for (key, item) in dictionary {
                if let object:AnyObject = item.object() {
                    result[key] = object
                }
            }
            return result
        case .ArrayValue(let array):
            var result = NSMutableArray()
            for item in array {
                if let object:AnyObject = item.object() {
                    result.addObject(object)
                }
            }
            return result
        case .SetValue(let set):
            return set
        case .ClusterValue(let cluster):
            // The four types declared as Clusters in RenderingEngine.swift
            if let bool: Bool = object() {
                return bool
            } else if let int: Int = object() {
                return int
            } else if let double: Double = object() {
                return double
            } else if let string: String = object() {
                return string
            } else {
                return nil
            }
        default:
            return nil
        }
    }
    
    public func object() -> MustacheCluster? {
        switch type {
        case .ClusterValue(let cluster):
            return cluster
        default:
            return nil
        }
    }
    
    public func object() -> [String: Value]? {
        switch type {
        case .DictionaryValue(let dictionary):
            return dictionary
        default:
            return nil
        }
    }
    
    public func object() -> [Value]? {
        switch type {
        case .ArrayValue(let array):
            return array
        default:
            return nil
        }
    }
    
    public func toInt() -> Int? {
        if let int: Int = object() {
            return int
        } else if let double: Double = object() {
            return Int(double)
        } else {
            return nil
        }
    }
    
    public func toDouble() -> Double? {
        if let int: Int = object() {
            return Double(int)
        } else if let double: Double = object() {
            return double
        } else {
            return nil
        }
    }
    
    public func toString() -> String? {
        switch type {
        case .None:
            return nil
        case .AnyObjectValue(let object):
            return "\(object)"
        case .DictionaryValue(let dictionary):
            return "\(dictionary)"
        case .ArrayValue(let array):
            return "\(array)"
        case .SetValue(let set):
            return "\(set)"
        case .ClusterValue(let cluster):
            return "\(cluster)"
        }
    }
    
}


// =============================================================================
// MARK: - Convenience value unwrapping

extension Value {

    public func object() -> MustacheFilter? {
        return (object() as MustacheCluster?)?.mustacheFilter
    }
    
    public func object() -> MustacheInspectable? {
        return (object() as MustacheCluster?)?.mustacheInspectable
    }
    
    public func object() -> MustacheRenderable? {
        return (object() as MustacheCluster?)?.mustacheRenderable
    }
    
    public func object() -> MustacheTagObserver? {
        return (object() as MustacheCluster?)?.mustacheTagObserver
    }
    
    public func object<T: MustacheWrappable>() -> T? {
        return Value.wrappableFromCluster(object() as MustacheCluster?) as? T
    }
    
    public func object<T: NSObjectProtocol>() -> T? {
        return (object() as AnyObject?) as? T
    }
    
}


// =============================================================================
// MARK: - DebugPrintable

extension Value: DebugPrintable {
    
    public var debugDescription: String {
        switch type {
        case .None:
            return "Value.None"
        case .AnyObjectValue(let object):
            return "Value.AnyObjectValue(\(object))"
        case .DictionaryValue(let dictionary):
            return "Value.DictionaryValue(\(dictionary.debugDescription))"
        case .ArrayValue(let array):
            return "Value.ArrayValue(\(array.debugDescription))"
        case .SetValue(let set):
            return "Value.SetValue(\(set))"
        case .ClusterValue(let cluster):
            return "Value.ClusterValue(\(cluster))"
        }
    }
}


// =============================================================================
// MARK: - Key extraction

extension Value {
    
    subscript(identifier: String) -> Value {
        switch type {
        case .None:
            return Value()
        case .AnyObjectValue(let object):
            return Value(object.valueForKey?(identifier))
        case .DictionaryValue(let dictionary):
            if let mustacheValue = dictionary[identifier] {
                return mustacheValue
            } else {
                return Value()
            }
        case .ArrayValue(let array):
            switch identifier {
            case "count":
                return Value(countElements(array))
            case "firstObject":
                if let first = array.first {
                    return first
                } else {
                    return Value()
                }
            case "lastObject":
                if let last = array.last {
                    return last
                } else {
                    return Value()
                }
            default:
                return Value()
            }
        case .SetValue(let set):
            switch identifier {
            case "count":
                return Value(set.count)
            case "anyObject":
                return Value(set.anyObject())
            default:
                return Value()
            }
        case .ClusterValue(let cluster):
            if let value = cluster.mustacheInspectable?.valueForMustacheKey(identifier) {
                return value
            } else {
                return Value()
            }
        }
    }
}


// =============================================================================
// MARK: - Rendering

extension Value {

    var mustacheBool: Bool {
        switch type {
        case .None:
            return false
        case .DictionaryValue:
            return true
        case .ArrayValue(let array):
            return countElements(array) > 0
        case .SetValue(let set):
            return set.count > 0
        case .AnyObjectValue(let object):
            return true
        case .ClusterValue(let cluster):
            return cluster.mustacheBool
        }
    }
    
    public func render(info: RenderingInfo, error: NSErrorPointer) -> Rendering? {
        let tag = info.tag
        switch type {
        case .None:
            switch tag.type {
            case .Variable:
                return Rendering("")
            case .Section:
                return info.tag.render(info.context, error: error)
            }
        case .DictionaryValue(let dictionary):
            switch tag.type {
            case .Variable:
                return Rendering("\(dictionary)")
            case .Section:
                return info.tag.render(info.context.extendedContext(value: self), error: error)
            }
        case .ArrayValue(let array):
            if info.enumerationItem {
                return info.tag.render(info.context.extendedContext(value: self), error: error)
            } else {
                var buffer = ""
                var contentType: ContentType?
                let enumerationRenderingInfo = info.renderingInfoBySettingEnumerationItem()
                for item in array {
                    if let itemRendering = item.render(enumerationRenderingInfo, error: error) {
                        if contentType == nil {
                            contentType = itemRendering.contentType
                            buffer += itemRendering.string
                        } else if contentType == itemRendering.contentType {
                            buffer += itemRendering.string
                        } else {
                            if error != nil {
                                error.memory = NSError(domain: GRMustacheErrorDomain, code: GRMustacheErrorCodeRenderingError, userInfo: [NSLocalizedDescriptionKey: "Content type mismatch"])
                            }
                            return nil
                        }
                    } else {
                        return nil
                    }
                }
                
                if let contentType = contentType {
                    return Rendering(buffer, contentType)
                } else {
                    switch tag.type {
                    case .Variable:
                        return Rendering("")
                    case .Section:
                        return info.tag.render(info.context, error: error)
                    }
                }
            }
        case .SetValue(let set):
            if info.enumerationItem {
                return info.tag.render(info.context.extendedContext(value: self), error: error)
            } else {
                var buffer = ""
                var contentType: ContentType?
                let enumerationRenderingInfo = info.renderingInfoBySettingEnumerationItem()
                for item in set {
                    if let itemRendering = Value(item).render(enumerationRenderingInfo, error: error) {
                        if contentType == nil {
                            contentType = itemRendering.contentType
                            buffer += itemRendering.string
                        } else if contentType == itemRendering.contentType {
                            buffer += itemRendering.string
                        } else {
                            if error != nil {
                                error.memory = NSError(domain: GRMustacheErrorDomain, code: GRMustacheErrorCodeRenderingError, userInfo: [NSLocalizedDescriptionKey: "Content type mismatch"])
                            }
                            return nil
                        }
                    } else {
                        return nil
                    }
                }

                if let contentType = contentType {
                    return Rendering(buffer, contentType)
                } else {
                    switch tag.type {
                    case .Variable:
                        return Rendering("")
                    case .Section:
                        return info.tag.render(info.context, error: error)
                    }
                }
            }
        case .AnyObjectValue(let object):
            switch tag.type {
            case .Variable:
                return Rendering("\(object)")
            case .Section:
                return info.tag.render(info.context.extendedContext(value: self), error: error)
            }
        case .ClusterValue(let cluster):
            if let renderable = cluster.mustacheRenderable {
                return renderable.mustacheRender(info, error: error)
            } else {
                return info.tag.render(info.context.extendedContext(value: self), error: error)
            }
        }
    }
}
