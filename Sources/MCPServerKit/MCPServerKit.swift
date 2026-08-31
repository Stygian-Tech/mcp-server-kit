import Foundation

public enum MCPServerKitVersion {
  public static let current = 1
}

public enum MCPProtocolVersion: String, CaseIterable, Codable, Sendable {
  case v2024_11_05 = "2024-11-05"
  case v2025_06_18 = "2025-06-18"
  case v2025_11_25 = "2025-11-25"

  public static let fallback = v2024_11_05

  public static func negotiated(requested: String?) -> String {
    let trimmed = requested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty,
          let version = MCPProtocolVersion(rawValue: trimmed),
          allCases.contains(version) else {
      return fallback.rawValue
    }
    return version.rawValue
  }
}

/// A recursive representation of a JSON value that preserves nested wire arguments.
public enum MCPJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case integer(Int)
  case number(Double)
  case string(String)
  case array([MCPJSONValue])
  case object([String: MCPJSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([MCPJSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: MCPJSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Value is not valid JSON"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }

  /// Returns the legacy string representation for scalar JSON values.
  public var stringValue: String? {
    switch self {
    case .string(let value):
      return value
    case .integer(let value):
      return String(value)
    case .number(let value):
      return String(value)
    case .bool(let value):
      return String(value)
    case .null, .array, .object:
      return nil
    }
  }
}

public struct MCPMethod: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: StringLiteralType) {
    self.init(rawValue: value)
  }

  public static let initialize = MCPMethod(rawValue: "initialize")
  public static let toolsList = MCPMethod(rawValue: "tools/list")
  public static let toolsCall = MCPMethod(rawValue: "tools/call")
  public static let resourcesList = MCPMethod(rawValue: "resources/list")
  public static let resourcesRead = MCPMethod(rawValue: "resources/read")
  public static let resourcesSubscribe = MCPMethod(rawValue: "resources/subscribe")
  public static let resourcesUnsubscribe = MCPMethod(rawValue: "resources/unsubscribe")
  public static let promptsList = MCPMethod(rawValue: "prompts/list")
  public static let promptsGet = MCPMethod(rawValue: "prompts/get")
  public static let notificationsInitialized = MCPMethod(rawValue: "notifications/initialized")
  public static let notificationsCancelled = MCPMethod(rawValue: "notifications/cancelled")
}

public enum MCPJSONRPCID: Codable, Equatable, Hashable, Sendable {
  case int(Int)
  case string(String)
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let intValue = try? container.decode(Int.self) {
      self = .int(intValue)
    } else if let stringValue = try? container.decode(String.self) {
      self = .string(stringValue)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "JSON-RPC id must be an integer, string, or null"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .int(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }
}

public struct MCPRequest: Codable, Equatable, Sendable {
  public let jsonrpc: String?
  public let id: MCPJSONRPCID?
  public let method: MCPMethod
  public let params: MCPRequestParams?

  public init(jsonrpc: String?, id: MCPJSONRPCID?, method: MCPMethod, params: MCPRequestParams?) {
    self.jsonrpc = jsonrpc
    self.id = id
    self.method = method
    self.params = params
  }
}

public struct MCPRequestParams: Codable, Equatable, Sendable {
  public let name: String?
  public let arguments: [String: MCPJSONValue]?
  public let uri: String?
  public let protocolVersion: String?

  /// A compatibility view of scalar arguments used by pre-2025 handlers.
  /// Nested objects, arrays, and null values are omitted.
  public var stringArguments: [String: String]? {
    guard let arguments else { return nil }
    let values = arguments.compactMapValues(\.stringValue)
    return values.isEmpty ? nil : values
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case arguments
    case uri
    case protocolVersion
  }

  public init(
    name: String?,
    arguments: [String: MCPJSONValue]?,
    uri: String? = nil,
    protocolVersion: String? = nil
  ) {
    self.name = name
    self.arguments = arguments
    self.uri = uri
    self.protocolVersion = protocolVersion
  }

  /// Source-compatible convenience for callers that still construct scalar string arguments.
  public init(
    name: String?,
    arguments: [String: String],
    uri: String? = nil,
    protocolVersion: String? = nil
  ) {
    self.init(
      name: name,
      arguments: arguments.mapValues(MCPJSONValue.string),
      uri: uri,
      protocolVersion: protocolVersion
    )
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    uri = try container.decodeIfPresent(String.self, forKey: .uri)
    protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
    arguments = try container.decodeIfPresent([String: MCPJSONValue].self, forKey: .arguments)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encodeIfPresent(arguments, forKey: .arguments)
    try container.encodeIfPresent(uri, forKey: .uri)
    try container.encodeIfPresent(protocolVersion, forKey: .protocolVersion)
  }

}

public struct MCPErrorObject: Codable, Equatable, Sendable {
  public let code: Int
  public let message: String
  public let data: MCPJSONValue?

  public init(code: Int, message: String, data: MCPJSONValue? = nil) {
    self.code = code
    self.message = message
    self.data = data
  }
}

public struct MCPErrorResponse: Codable, Equatable, Sendable {
  public let jsonrpc: String
  public let id: MCPJSONRPCID?
  public let error: MCPErrorObject

  public init(jsonrpc: String = "2.0", id: MCPJSONRPCID?, error: MCPErrorObject) {
    self.jsonrpc = jsonrpc
    self.id = id
    self.error = error
  }
}

public struct MCPSuccessResponse<Result: Codable & Sendable>: Codable, Sendable {
  public let jsonrpc: String
  public let id: MCPJSONRPCID?
  public let result: Result

  public init(jsonrpc: String = "2.0", id: MCPJSONRPCID?, result: Result) {
    self.jsonrpc = jsonrpc
    self.id = id
    self.result = result
  }
}

public struct MCPInitializeResult: Codable, Equatable, Sendable {
  public let protocolVersion: String
  public let capabilities: MCPServerCapabilities
  public let serverInfo: MCPServerInfo
  public let instructions: String?

  public init(
    protocolVersion: String,
    capabilities: MCPServerCapabilities,
    serverInfo: MCPServerInfo,
    instructions: String?
  ) {
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities
    self.serverInfo = serverInfo
    self.instructions = instructions
  }
}

public struct MCPServerCapabilities: Codable, Equatable, Sendable {
  public let tools: MCPToolsCapability?
  public let resources: MCPResourcesCapability?
  public let prompts: MCPPromptsCapability?

  public init(
    tools: MCPToolsCapability?,
    resources: MCPResourcesCapability?,
    prompts: MCPPromptsCapability?
  ) {
    self.tools = tools
    self.resources = resources
    self.prompts = prompts
  }
}

public struct MCPToolsCapability: Codable, Equatable, Sendable {
  public let listChanged: Bool?

  public init(listChanged: Bool?) {
    self.listChanged = listChanged
  }
}

public struct MCPResourcesCapability: Codable, Equatable, Sendable {
  public let subscribe: Bool?
  public let listChanged: Bool?

  public init(subscribe: Bool?, listChanged: Bool?) {
    self.subscribe = subscribe
    self.listChanged = listChanged
  }
}

public struct MCPPromptsCapability: Codable, Equatable, Sendable {
  public let listChanged: Bool?

  public init(listChanged: Bool?) {
    self.listChanged = listChanged
  }
}

public struct MCPServerInfo: Codable, Equatable, Sendable {
  public let name: String
  public let version: String
  public let title: String?
  public let description: String?
  public let websiteUrl: String?

  public init(name: String, version: String, title: String?, description: String?, websiteUrl: String?) {
    self.name = name
    self.version = version
    self.title = title
    self.description = description
    self.websiteUrl = websiteUrl
  }
}

public struct MCPToolsListResult: Codable, Equatable, Sendable {
  public let tools: [MCPTool]
  public let nextCursor: String?

  public init(tools: [MCPTool], nextCursor: String? = nil) {
    self.tools = tools
    self.nextCursor = nextCursor
  }
}

public struct MCPTool: Codable, Equatable, Sendable {
  public let name: String
  public let title: String?
  public let description: String?
  public let inputSchema: MCPInputSchema?
  public let outputSchema: MCPInputSchema?
  public let icons: [MCPToolIcon]?
  public let annotations: MCPToolAnnotations?

  public init(
    name: String,
    description: String?,
    inputSchema: MCPInputSchema?,
    title: String? = nil,
    outputSchema: MCPInputSchema? = nil,
    icons: [MCPToolIcon]? = nil,
    annotations: MCPToolAnnotations? = nil
  ) {
    self.name = name
    self.title = title
    self.description = description
    self.inputSchema = inputSchema
    self.outputSchema = outputSchema
    self.icons = icons
    self.annotations = annotations
  }
}

public struct MCPToolIcon: Codable, Equatable, Sendable {
  public let src: String
  public let mimeType: String?
  public let sizes: [String]?
  public let theme: String?

  public init(src: String, mimeType: String? = nil, sizes: [String]? = nil, theme: String? = nil) {
    self.src = src
    self.mimeType = mimeType
    self.sizes = sizes
    self.theme = theme
  }
}

public struct MCPToolAnnotations: Codable, Equatable, Sendable {
  public let title: String?
  public let readOnlyHint: Bool?
  public let destructiveHint: Bool?
  public let idempotentHint: Bool?
  public let openWorldHint: Bool?

  public init(
    title: String? = nil,
    readOnlyHint: Bool? = nil,
    destructiveHint: Bool? = nil,
    idempotentHint: Bool? = nil,
    openWorldHint: Bool? = nil
  ) {
    self.title = title
    self.readOnlyHint = readOnlyHint
    self.destructiveHint = destructiveHint
    self.idempotentHint = idempotentHint
    self.openWorldHint = openWorldHint
  }
}

/// JSON Schema subset used by MCP tool input and output declarations.
/// This is a reference type so schemas can recursively describe objects and arrays.
public final class MCPJSONSchema: Codable, Equatable, Sendable {
  public let type: String?
  public let description: String?
  public let properties: [String: MCPJSONSchema]?
  public let required: [String]?
  public let enumValues: [MCPJSONValue]?
  public let items: MCPJSONSchema?
  public let additionalProperties: Bool?
  public let minimum: Double?
  public let maximum: Double?
  public let exclusiveMinimum: Double?
  public let exclusiveMaximum: Double?
  public let minLength: Int?
  public let maxLength: Int?
  public let pattern: String?
  public let format: String?
  public let minItems: Int?
  public let maxItems: Int?
  public let uniqueItems: Bool?

  private enum CodingKeys: String, CodingKey {
    case type
    case description
    case properties
    case required
    case enumValues = "enum"
    case items
    case additionalProperties
    case minimum
    case maximum
    case exclusiveMinimum
    case exclusiveMaximum
    case minLength
    case maxLength
    case pattern
    case format
    case minItems
    case maxItems
    case uniqueItems
  }

  public init(
    type: String? = nil,
    properties: [String: MCPJSONSchema]? = nil,
    description: String? = nil,
    required: [String]? = nil,
    enumValues: [MCPJSONValue]? = nil,
    items: MCPJSONSchema? = nil,
    additionalProperties: Bool? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil,
    exclusiveMinimum: Double? = nil,
    exclusiveMaximum: Double? = nil,
    minLength: Int? = nil,
    maxLength: Int? = nil,
    pattern: String? = nil,
    format: String? = nil,
    minItems: Int? = nil,
    maxItems: Int? = nil,
    uniqueItems: Bool? = nil
  ) {
    self.type = type
    self.description = description
    self.properties = properties
    self.required = required
    self.enumValues = enumValues
    self.items = items
    self.additionalProperties = additionalProperties
    self.minimum = minimum
    self.maximum = maximum
    self.exclusiveMinimum = exclusiveMinimum
    self.exclusiveMaximum = exclusiveMaximum
    self.minLength = minLength
    self.maxLength = maxLength
    self.pattern = pattern
    self.format = format
    self.minItems = minItems
    self.maxItems = maxItems
    self.uniqueItems = uniqueItems
  }

  public static func == (lhs: MCPJSONSchema, rhs: MCPJSONSchema) -> Bool {
    lhs.type == rhs.type
      && lhs.description == rhs.description
      && lhs.properties == rhs.properties
      && lhs.required == rhs.required
      && lhs.enumValues == rhs.enumValues
      && lhs.items == rhs.items
      && lhs.additionalProperties == rhs.additionalProperties
      && lhs.minimum == rhs.minimum
      && lhs.maximum == rhs.maximum
      && lhs.exclusiveMinimum == rhs.exclusiveMinimum
      && lhs.exclusiveMaximum == rhs.exclusiveMaximum
      && lhs.minLength == rhs.minLength
      && lhs.maxLength == rhs.maxLength
      && lhs.pattern == rhs.pattern
      && lhs.format == rhs.format
      && lhs.minItems == rhs.minItems
      && lhs.maxItems == rhs.maxItems
      && lhs.uniqueItems == rhs.uniqueItems
  }

  public static func fromCapabilitySchemaJson(_ raw: String?) -> MCPJSONSchema {
    guard let raw,
          let data = raw.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(MCPJSONSchema.self, from: data) else {
      return MCPJSONSchema(type: "object", properties: [:])
    }
    return decoded
  }
}

public typealias MCPInputSchema = MCPJSONSchema
public typealias MCPPropertySchema = MCPJSONSchema

public struct MCPToolTextContent: Codable, Equatable, Sendable {
  public let type: String
  public let text: String

  public init(type: String = "text", text: String) {
    self.type = type
    self.text = text
  }
}

public struct MCPToolResourceLinkContent: Codable, Equatable, Sendable {
  public let type: String
  public let uri: String
  public let name: String
  public let title: String?
  public let description: String?
  public let mimeType: String?
  public let size: Int?

  public init(
    type: String = "resource_link",
    uri: String,
    name: String,
    title: String? = nil,
    description: String? = nil,
    mimeType: String? = nil,
    size: Int? = nil
  ) {
    self.type = type
    self.uri = uri
    self.name = name
    self.title = title
    self.description = description
    self.mimeType = mimeType
    self.size = size
  }
}

public enum MCPToolContent: Codable, Equatable, Sendable {
  case text(MCPToolTextContent)
  case resourceLink(MCPToolResourceLinkContent)

  private enum CodingKeys: String, CodingKey {
    case type
  }

  private enum ContentType: String, Codable {
    case text
    case resourceLink = "resource_link"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(ContentType.self, forKey: .type) {
    case .text:
      self = .text(try MCPToolTextContent(from: decoder))
    case .resourceLink:
      self = .resourceLink(try MCPToolResourceLinkContent(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .text(let content):
      try content.encode(to: encoder)
    case .resourceLink(let content):
      try content.encode(to: encoder)
    }
  }
}

public struct MCPToolCallResult: Codable, Equatable, Sendable {
  public let content: [MCPToolContent]
  public let structuredContent: MCPJSONValue?
  public let isError: Bool?

  public init(
    content: [MCPToolContent],
    structuredContent: MCPJSONValue? = nil,
    isError: Bool? = nil
  ) {
    self.content = content
    self.structuredContent = structuredContent
    self.isError = isError
  }

  public init(text: String, structuredContent: MCPJSONValue? = nil, isError: Bool? = nil) {
    self.init(
      content: [.text(MCPToolTextContent(text: text))],
      structuredContent: structuredContent,
      isError: isError
    )
  }
}

public struct MCPResourcesListResult: Codable, Equatable, Sendable {
  public let resources: [MCPResource]
  public let nextCursor: String?

  public init(resources: [MCPResource], nextCursor: String? = nil) {
    self.resources = resources
    self.nextCursor = nextCursor
  }
}

public struct MCPResource: Codable, Equatable, Sendable {
  public let uri: String
  public let name: String?
  public let description: String?
  public let mimeType: String?
  public let useWhen: [String]?
  public let avoidWhen: [String]?
  public let failureModes: [String]?
  public let invokeFirst: Bool?

  enum CodingKeys: String, CodingKey {
    case uri
    case name
    case description
    case mimeType
    case useWhen = "use_when"
    case avoidWhen = "avoid_when"
    case failureModes = "failure_modes"
    case invokeFirst = "invoke_first"
  }

  public init(
    uri: String,
    name: String?,
    description: String?,
    mimeType: String?,
    useWhen: [String]?,
    avoidWhen: [String]?,
    failureModes: [String]?,
    invokeFirst: Bool?
  ) {
    self.uri = uri
    self.name = name
    self.description = description
    self.mimeType = mimeType
    self.useWhen = useWhen
    self.avoidWhen = avoidWhen
    self.failureModes = failureModes
    self.invokeFirst = invokeFirst
  }
}

public struct MCPResourceContent: Codable, Equatable, Sendable {
  public let uri: String
  public let mimeType: String
  public let text: String

  public init(uri: String, mimeType: String, text: String) {
    self.uri = uri
    self.mimeType = mimeType
    self.text = text
  }
}

public struct MCPResourcesReadResult: Codable, Equatable, Sendable {
  public let contents: [MCPResourceContent]

  public init(contents: [MCPResourceContent]) {
    self.contents = contents
  }
}

public struct MCPPromptsListResult: Codable, Equatable, Sendable {
  public let prompts: [MCPPrompt]
  public let nextCursor: String?

  public init(prompts: [MCPPrompt], nextCursor: String? = nil) {
    self.prompts = prompts
    self.nextCursor = nextCursor
  }
}

public struct MCPPrompt: Codable, Equatable, Sendable {
  public let name: String
  public let description: String?
  public let arguments: [MCPPromptArgument]?

  public init(name: String, description: String?, arguments: [MCPPromptArgument]?) {
    self.name = name
    self.description = description
    self.arguments = arguments
  }
}

public struct MCPPromptArgument: Codable, Equatable, Sendable {
  public let name: String
  public let description: String?
  public let required: Bool?

  public init(name: String, description: String?, required: Bool?) {
    self.name = name
    self.description = description
    self.required = required
  }
}

public struct MCPPromptMessage: Codable, Equatable, Sendable {
  public let role: String
  public let content: MCPPromptTextContent

  public init(role: String, content: MCPPromptTextContent) {
    self.role = role
    self.content = content
  }
}

public struct MCPPromptTextContent: Codable, Equatable, Sendable {
  public let type: String
  public let text: String

  public init(type: String = "text", text: String) {
    self.type = type
    self.text = text
  }
}

public struct MCPPromptsGetResult: Codable, Equatable, Sendable {
  public let description: String?
  public let messages: [MCPPromptMessage]

  public init(description: String?, messages: [MCPPromptMessage]) {
    self.description = description
    self.messages = messages
  }
}

public struct MCPResourceMeta: Equatable, Sendable {
  public let uri: String
  public let mimeType: String
  public let useWhen: [String]?
  public let avoidWhen: [String]?
  public let failureModes: [String]?
  public let invokeFirst: Bool?

  public init(
    uri: String,
    mimeType: String,
    useWhen: [String]?,
    avoidWhen: [String]?,
    failureModes: [String]?,
    invokeFirst: Bool?
  ) {
    self.uri = uri
    self.mimeType = mimeType
    self.useWhen = useWhen
    self.avoidWhen = avoidWhen
    self.failureModes = failureModes
    self.invokeFirst = invokeFirst
  }
}

public enum MCPToolSchemaBuilder {
  public static let resourceURIScheme = "ctx"
  public static let resourceURIHost = "skill"

  public static func toolInputSchemaJson(description: String?, summary: String?) -> String {
    let blurb = [description, summary]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    let detailHelp: String
    if let blurb, !blurb.isEmpty {
      let capped = blurb.count > 480 ? String(blurb.prefix(480)) + "..." : blurb
      detailHelp = "Optional extra context. Skill summary: \(capped)"
    } else {
      detailHelp = "Optional extra context or question for this skill."
    }
    let payload = ToolSchemaPayload(
      type: "object",
      properties: ["detail": .init(type: "string", description: detailHelp)],
      additionalProperties: false
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(payload), let string = String(data: data, encoding: .utf8) {
      return string
    }
    return #"{"type":"object","properties":{}}"#
  }

  public static func resourceMetaJson(skillName: String) -> String {
    resourceMetaJson(skillName: skillName, useWhen: nil, avoidWhen: nil, failureModes: nil, invokeFirst: nil)
  }

  public static func resourceMetaJson(
    skillName: String,
    useWhen: [String]?,
    avoidWhen: [String]?,
    failureModes: [String]?,
    invokeFirst: Bool?
  ) -> String {
    var payload: [String: Any] = [
      "uri": resourceURI(skillName: skillName),
      "mimeType": "text/markdown",
    ]
    if let useWhen, !useWhen.isEmpty {
      payload["use_when"] = useWhen
    }
    if let avoidWhen, !avoidWhen.isEmpty {
      payload["avoid_when"] = avoidWhen
    }
    if let failureModes, !failureModes.isEmpty {
      payload["failure_modes"] = failureModes
    }
    if invokeFirst == true {
      payload["invoke_first"] = true
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
      return string
    }
    return #"{"uri":"ctx://skill/","mimeType":"text/markdown"}"#
  }

  public static func promptMetaJson() -> String {
    let payload: [String: Any] = ["arguments": []]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
      return string
    }
    return "{}"
  }

  public static func resourceURI(skillName: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let encoded = skillName.addingPercentEncoding(withAllowedCharacters: allowed) ?? skillName
    return "\(resourceURIScheme)://\(resourceURIHost)/\(encoded)"
  }

  public static func resourceSchemaJsonWithPatchedUri(schemaJson: String, skillName: String) -> String? {
    guard let data = schemaJson.data(using: .utf8),
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    object["uri"] = resourceURI(skillName: skillName)
    guard let output = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
      return nil
    }
    return String(data: output, encoding: .utf8)
  }

  public static func parseResourceMeta(_ schemaJson: String?) -> MCPResourceMeta? {
    guard let schemaJson,
          let data = schemaJson.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let uri = object["uri"] as? String,
          !uri.isEmpty else {
      return nil
    }
    return MCPResourceMeta(
      uri: uri,
      mimeType: (object["mimeType"] as? String) ?? "text/markdown",
      useWhen: object["use_when"] as? [String],
      avoidWhen: object["avoid_when"] as? [String],
      failureModes: object["failure_modes"] as? [String],
      invokeFirst: object["invoke_first"] as? Bool
    )
  }

  public static func resourceReadPreamble(meta: MCPResourceMeta, skillSummary: String?) -> String? {
    var lines: [String] = []
    if meta.invokeFirst == true {
      lines.append("**Invoke first:** consider loading this resource before other skills on the same task.")
    }
    if let useWhen = meta.useWhen, !useWhen.isEmpty {
      lines.append("**Read when:**")
      lines.append(contentsOf: useWhen.map { "- \($0)" })
    }
    if let avoidWhen = meta.avoidWhen, !avoidWhen.isEmpty {
      lines.append("**Skip when:**")
      lines.append(contentsOf: avoidWhen.map { "- \($0)" })
    }
    if let failureModes = meta.failureModes, !failureModes.isEmpty {
      lines.append("**Failure modes / fallbacks:**")
      lines.append(contentsOf: failureModes.map { "- \($0)" })
    }
    guard !lines.isEmpty else {
      return nil
    }
    if let skillSummary, !skillSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lines.insert("**Summary:** \(skillSummary)", at: 0)
    }
    return lines.joined(separator: "\n")
  }
}

private struct ToolSchemaPayload: Encodable {
  let type: String
  let properties: [String: ToolSchemaProperty]
  let additionalProperties: Bool
}

private struct ToolSchemaProperty: Encodable {
  let type: String
  let description: String?
}

public enum MCPDispatchError: Error, Equatable, Sendable {
  case methodNotFound(String)
}

public struct MCPDispatcher<Context: Sendable>: Sendable {
  public typealias Handler = @Sendable (MCPRequest, Context) async throws -> String

  private let handlers: [MCPMethod: Handler]

  public init(handlers: [MCPMethod: Handler] = [:]) {
    self.handlers = handlers
  }

  public func register(_ method: MCPMethod, handler: @escaping Handler) -> MCPDispatcher {
    var next = handlers
    next[method] = handler
    return MCPDispatcher(handlers: next)
  }

  public func dispatch(_ request: MCPRequest, context: Context) async throws -> String {
    guard let handler = handlers[request.method] else {
      throw MCPDispatchError.methodNotFound(request.method.rawValue)
    }
    return try await handler(request, context)
  }
}
