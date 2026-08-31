import Foundation
import MCPServerKit
import Testing

@Suite struct StygianMCPTests {
  @Test func decodesJSONRPCIdsAndParams() throws {
    let payload = Data(#"{"jsonrpc":"2.0","id":"abc","method":"tools/call","params":{"name":"summarize","arguments":{"count":3,"enabled":true,"detail":"short"}}}"#.utf8)

    let request = try JSONDecoder().decode(MCPRequest.self, from: payload)

    #expect(request.id == .string("abc"))
    #expect(request.method == .toolsCall)
    #expect(request.params?.name == "summarize")
    #expect(request.params?.stringArguments == ["count": "3", "enabled": "true", "detail": "short"])
  }

  @Test func preservesNestedToolArgumentsThroughRoundTrip() throws {
    let payload = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"resolve","arguments":{"filters":{"tags":["swift","mcp"],"active":true},"limit":10,"threshold":0.75,"empty":null}}}"#.utf8)

    let request = try JSONDecoder().decode(MCPRequest.self, from: payload)

    #expect(request.params?.arguments?["filters"] == .object([
      "tags": .array([.string("swift"), .string("mcp")]),
      "active": .bool(true),
    ]))
    #expect(request.params?.arguments?["limit"] == .integer(10))
    #expect(request.params?.arguments?["threshold"] == .number(0.75))
    #expect(request.params?.arguments?["empty"] == .null)
    #expect(request.params?.stringArguments == ["limit": "10", "threshold": "0.75"])

    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(MCPRequest.self, from: encoded)
    #expect(decoded == request)
  }

  @Test func preservesListCursorThroughRoundTrip() throws {
    let payload = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"cursor":"page-2"}}"#.utf8)
    let request = try JSONDecoder().decode(MCPRequest.self, from: payload)
    #expect(request.params?.cursor == "page-2")
    #expect(try JSONDecoder().decode(MCPRequest.self, from: JSONEncoder().encode(request)) == request)
  }

  @Test func encodesInitializeResultWithCapabilities() throws {
    let result = MCPInitializeResult(
      protocolVersion: MCPProtocolVersion.negotiated(requested: "2024-11-05"),
      capabilities: MCPServerCapabilities(
        tools: .init(listChanged: true),
        resources: .init(subscribe: true, listChanged: true),
        prompts: .init(listChanged: true)
      ),
      serverInfo: .init(
        name: "MyContextProtocol",
        version: "test",
        title: "MyContextProtocol",
        description: "Hosted MCP gateway",
        websiteUrl: "https://example.com"
      ),
      instructions: "Call the catalog first."
    )

    let data = try JSONEncoder().encode(result)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["protocolVersion"] as? String == MCPProtocolVersion.v2024_11_05.rawValue)
    #expect((object["serverInfo"] as? [String: Any])?["name"] as? String == "MyContextProtocol")
    #expect(object["instructions"] as? String == "Call the catalog first.")
  }

  @Test func buildsStableCapabilitySchemas() throws {
    let toolSchema = MCPToolSchemaBuilder.toolInputSchemaJson(
      description: String(repeating: "a", count: 520),
      summary: nil
    )
    let toolObject = try #require(JSONSerialization.jsonObject(with: Data(toolSchema.utf8)) as? [String: Any])
    let properties = try #require(toolObject["properties"] as? [String: Any])
    let detail = try #require(properties["detail"] as? [String: Any])

    #expect(toolObject["type"] as? String == "object")
    #expect(toolObject["additionalProperties"] as? Bool == false)
    #expect((detail["description"] as? String)?.contains("...") == true)

    let resourceJson = MCPToolSchemaBuilder.resourceMetaJson(
      skillName: "Skill Name",
      useWhen: ["when useful"],
      avoidWhen: nil,
      failureModes: ["fallback"],
      invokeFirst: true
    )
    let meta = try #require(MCPToolSchemaBuilder.parseResourceMeta(resourceJson))

    #expect(meta.uri == "ctx://skill/Skill%20Name")
    #expect(meta.mimeType == "text/markdown")
    #expect(meta.useWhen == ["when useful"])
    #expect(meta.failureModes == ["fallback"])
    #expect(meta.invokeFirst == true)
  }

  @Test func encodesRichToolSchemaAndMetadata() throws {
    let tagSchema = MCPJSONSchema(
      type: "string",
      enumValues: [.string("swift"), .string("mcp")],
      minLength: 1,
      maxLength: 32
    )
    let filterSchema = MCPJSONSchema(
      type: "object",
      properties: [
        "tags": MCPJSONSchema(type: "array", items: tagSchema, minItems: 1, uniqueItems: true),
        "score": MCPJSONSchema(type: "number", minimum: 0, maximum: 1),
      ],
      required: ["tags"],
      additionalProperties: false
    )
    let input = MCPInputSchema(
      type: "object",
      properties: ["filter": filterSchema],
      required: ["filter"],
      additionalProperties: false
    )
    let output = MCPInputSchema(
      type: "object",
      properties: ["matches": MCPJSONSchema(type: "integer", minimum: 0)],
      required: ["matches"],
      additionalProperties: false
    )
    let tool = MCPTool(
      name: "resolve_context",
      description: "Resolve matching context.",
      inputSchema: input,
      title: "Resolve context",
      outputSchema: output,
      icons: [.init(src: "https://example.com/icon.svg", mimeType: "image/svg+xml", sizes: ["any"], theme: "light")],
      annotations: .init(
        title: "Resolve context",
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      )
    )

    let data = try JSONEncoder().encode(tool)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let inputObject = try #require(object["inputSchema"] as? [String: Any])
    let filter = try #require((inputObject["properties"] as? [String: Any])?["filter"] as? [String: Any])
    let tags = try #require((filter["properties"] as? [String: Any])?["tags"] as? [String: Any])
    let items = try #require(tags["items"] as? [String: Any])
    let annotations = try #require(object["annotations"] as? [String: Any])

    #expect(object["title"] as? String == "Resolve context")
    #expect(object["outputSchema"] != nil)
    #expect(inputObject["required"] as? [String] == ["filter"])
    #expect(filter["additionalProperties"] as? Bool == false)
    #expect(items["enum"] as? [String] == ["swift", "mcp"])
    #expect(items["minLength"] as? Int == 1)
    #expect(tags["uniqueItems"] as? Bool == true)
    #expect(annotations["readOnlyHint"] as? Bool == true)
  }

  @Test func encodesStructuredToolResultWithTextFallback() throws {
    let result = MCPToolCallResult(
      text: "Found 2 skills.",
      structuredContent: .object([
        "count": .integer(2),
        "skills": .array([.string("swift"), .string("mcp")]),
      ])
    )

    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(MCPToolCallResult.self, from: data)

    #expect(decoded == result)
    #expect(decoded.content == [.text(MCPToolTextContent(text: "Found 2 skills."))])
    #expect(decoded.structuredContent == .object([
      "count": .integer(2),
      "skills": .array([.string("swift"), .string("mcp")]),
    ]))
  }

  @Test func encodesToolResourceLinks() throws {
    let result = MCPToolCallResult(
      content: [
        .text(MCPToolTextContent(text: "Read the complete skill package.")),
        .resourceLink(MCPToolResourceLinkContent(
          uri: "ctx://skill/swift/file/references/testing.md",
          name: "testing.md",
          title: "Swift testing reference",
          description: "Package-local testing guidance.",
          mimeType: "text/markdown",
          size: 512
        )),
      ]
    )

    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(MCPToolCallResult.self, from: data)

    #expect(decoded == result)
    guard case .resourceLink(let link) = decoded.content[1] else {
      Issue.record("Expected a resource link content block")
      return
    }
    #expect(link.uri == "ctx://skill/swift/file/references/testing.md")
    #expect(link.mimeType == "text/markdown")
  }

  @Test func negotiatesLatestProtocolAndFallsBackForUnknownVersions() {
    #expect(MCPProtocolVersion.negotiated(requested: "2025-03-26") == "2025-03-26")
    #expect(MCPProtocolVersion.negotiated(requested: "2025-11-25") == "2025-11-25")
    #expect(MCPProtocolVersion.negotiated(requested: " 2025-11-25 ") == "2025-11-25")
    #expect(MCPProtocolVersion.negotiated(requested: "2099-01-01") == MCPProtocolVersion.latest.rawValue)
    #expect(MCPProtocolVersion.negotiated(requested: nil) == MCPProtocolVersion.latest.rawValue)
    #expect(MCPProtocolVersion.missingHTTPHeaderFallback.rawValue == "2025-03-26")
  }

  @Test func encodesToolListCursorAndErrorData() throws {
    let list = MCPToolsListResult(tools: [], nextCursor: "page-2")
    let error = MCPErrorObject(
      code: -32602,
      message: "Invalid params",
      data: .object(["field": .string("arguments")])
    )

    #expect(try JSONDecoder().decode(MCPToolsListResult.self, from: JSONEncoder().encode(list)) == list)
    #expect(try JSONDecoder().decode(MCPErrorObject.self, from: JSONEncoder().encode(error)) == error)
  }

  @Test func legacyInitializersRemainSourceCompatible() {
    let params = MCPRequestParams(name: "legacy", arguments: ["detail": "short"])
    let property = MCPPropertySchema(type: "string", description: "Legacy property")
    let input = MCPInputSchema(type: "object", properties: ["detail": property])
    let tool = MCPTool(name: "legacy", description: "Legacy tool", inputSchema: input)
    let list = MCPToolsListResult(tools: [tool])
    let error = MCPErrorObject(code: -32601, message: "Method not found")

    #expect(params.stringArguments == ["detail": "short"])
    #expect(tool.title == nil)
    #expect(list.nextCursor == nil)
    #expect(error.data == nil)
  }

  @Test func dispatchesRegisteredMethodsAndMissingHandlers() async throws {
    let dispatcher = MCPDispatcher<String>()
      .register(.initialize) { request, context in
        #expect(request.method == .initialize)
        return "initialized \(context)"
      }

    let request = MCPRequest(jsonrpc: "2.0", id: .int(1), method: .initialize, params: nil)

    let result = try await dispatcher.dispatch(request, context: "project")
    #expect(result == "initialized project")
    await #expect(throws: MCPDispatchError.methodNotFound("tools/list")) {
      try await dispatcher.dispatch(
        MCPRequest(jsonrpc: "2.0", id: nil, method: .toolsList, params: nil),
        context: "project"
      )
    }
  }
}
