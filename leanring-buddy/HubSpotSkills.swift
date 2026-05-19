//
//  HubSpotSkills.swift
//  leanring-buddy
//

import Foundation

struct HubSpotSearchInput: Codable {
    let objectType: String
    let query: String
    let limit: Int?
}

struct HubSpotObjectIDInput: Codable {
    let objectType: String
    let id: String
}

struct HubSpotCreateNoteInput: Codable {
    let body: String
    let associatedObjectID: String?
    let associatedObjectType: String?
}

struct HubSpotCreateTaskInput: Codable {
    let title: String
    let body: String?
    let dueDate: Date?
    let associatedObjectID: String?
    let associatedObjectType: String?
}

struct HubSpotUpdateDealStageInput: Codable {
    let dealID: String
    let stageID: String
}

struct HubSpotLogEmailInput: Codable {
    let subject: String
    let body: String
    let associatedObjectID: String?
    let associatedObjectType: String?
}

enum HubSpotSkills {
    static func makeAll(client: HubSpotAPIClient = HubSpotAPIClient()) -> [YavenSkill] {
        [
            searchRecords(client: client),
            getContact(client: client),
            getCompany(client: client),
            getDeal(client: client),
            getNotes(client: client),
            getTasks(client: client),
            createNote(client: client),
            createTask(client: client),
            updateDealStage(client: client),
            logEmail(client: client),
            proposeUpdatePlan
        ]
    }

    private static func searchRecords(client: HubSpotAPIClient) -> YavenSkill {
        YavenSkill(
            name: "hubspot_search_records",
            kind: .read,
            inputSchema: "objectType:string, query:string, limit?:number"
        ) { input in
            let request: HubSpotSearchInput = try decode(input)
            return try client.searchRecords(
                objectType: request.objectType,
                query: request.query,
                limit: request.limit ?? 10
            )
        }
    }

    private static func getContact(client: HubSpotAPIClient) -> YavenSkill {
        getObjectSkill(name: "hubspot_get_contact", objectType: "contacts", client: client)
    }

    private static func getCompany(client: HubSpotAPIClient) -> YavenSkill {
        getObjectSkill(name: "hubspot_get_company", objectType: "companies", client: client)
    }

    private static func getDeal(client: HubSpotAPIClient) -> YavenSkill {
        getObjectSkill(name: "hubspot_get_deal", objectType: "deals", client: client)
    }

    private static func getNotes(client: HubSpotAPIClient) -> YavenSkill {
        getObjectSkill(name: "hubspot_get_notes", objectType: "notes", client: client)
    }

    private static func getTasks(client: HubSpotAPIClient) -> YavenSkill {
        getObjectSkill(name: "hubspot_get_tasks", objectType: "tasks", client: client)
    }

    private static func createNote(client: HubSpotAPIClient) -> YavenSkill {
        YavenSkill(
            name: "hubspot_create_note",
            kind: .write(requiresApproval: true),
            risk: .medium,
            inputSchema: "body:string, associatedObjectID?:string, associatedObjectType?:string"
        ) { input in
            let request: HubSpotCreateNoteInput = try decode(input)
            return try client.createNote(request)
        }
    }

    private static func createTask(client: HubSpotAPIClient) -> YavenSkill {
        YavenSkill(
            name: "hubspot_create_task",
            kind: .write(requiresApproval: true),
            risk: .medium,
            inputSchema: "title:string, body?:string, dueDate?:date, associatedObjectID?:string, associatedObjectType?:string"
        ) { input in
            let request: HubSpotCreateTaskInput = try decode(input)
            return try client.createTask(request)
        }
    }

    private static func updateDealStage(client: HubSpotAPIClient) -> YavenSkill {
        YavenSkill(
            name: "hubspot_update_deal_stage",
            kind: .write(requiresApproval: true),
            risk: .high,
            inputSchema: "dealID:string, stageID:string"
        ) { input in
            let request: HubSpotUpdateDealStageInput = try decode(input)
            return try client.updateDealStage(request)
        }
    }

    private static func logEmail(client: HubSpotAPIClient) -> YavenSkill {
        YavenSkill(
            name: "hubspot_log_email",
            kind: .write(requiresApproval: true),
            risk: .medium,
            inputSchema: "subject:string, body:string, associatedObjectID?:string, associatedObjectType?:string"
        ) { input in
            let request: HubSpotLogEmailInput = try decode(input)
            return try client.logEmail(request)
        }
    }

    static let proposeUpdatePlan = YavenSkill(
        name: "hubspot_propose_update_plan",
        kind: .structuredOutput,
        inputSchema: "freeform CRM context",
        outputSchema: "approval-first CRM update plan"
    ) { _ in
        "HubSpot update plan presented to user, awaiting approval."
    }

    private static func getObjectSkill(
        name: String,
        objectType: String,
        client: HubSpotAPIClient
    ) -> YavenSkill {
        YavenSkill(
            name: name,
            kind: .read,
            inputSchema: "id:string"
        ) { input in
            let id = try requiredString(from: input["id"], key: "id")
            return try client.getObject(objectType: objectType, id: id)
        }
    }

    private static func decode<T: Decodable>(_ input: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: input, options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private static func requiredString(from value: Any?, key: String) throws -> String {
        guard let string = value as? String, !string.isEmpty else {
            throw NSError(domain: "HubSpotSkills", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(key) is required."
            ])
        }
        return string
    }
}

final class HubSpotAPIClient {
    private enum Constants {
        static let tokenDefaultsKey = "com.yaven.hubspot.accessToken"
    }

    private let baseURL: URL
    private let session: URLSession
    private let accessTokenProvider: () -> String?
    private let encoder = JSONEncoder()

    init(
        baseURL: URL = URL(string: "https://api.hubapi.com")!,
        session: URLSession = .shared,
        accessTokenProvider: @escaping () -> String? = {
            UserDefaults.standard.string(forKey: Constants.tokenDefaultsKey) ??
            ProcessInfo.processInfo.environment["HUBSPOT_ACCESS_TOKEN"]
        }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.accessTokenProvider = accessTokenProvider
        encoder.dateEncodingStrategy = .iso8601
    }

    func searchRecords(objectType: String, query: String, limit: Int) throws -> String {
        let body: [String: Any] = [
            "query": query,
            "limit": max(1, min(limit, 25))
        ]
        return try sendSync(path: "/crm/v3/objects/\(objectType)/search", method: "POST", jsonBody: body)
    }

    func getObject(objectType: String, id: String) throws -> String {
        try sendSync(path: "/crm/v3/objects/\(objectType)/\(id)", method: "GET")
    }

    func createNote(_ input: HubSpotCreateNoteInput) throws -> String {
        let body = makeObjectBody(properties: [
            "hs_note_body": input.body,
            "hs_timestamp": isoTimestamp()
        ], associatedObjectID: input.associatedObjectID, associatedObjectType: input.associatedObjectType)
        return try sendSync(path: "/crm/v3/objects/notes", method: "POST", jsonBody: body)
    }

    func createTask(_ input: HubSpotCreateTaskInput) throws -> String {
        var properties: [String: Any] = [
            "hs_task_subject": input.title,
            "hs_task_body": input.body ?? "",
            "hs_timestamp": input.dueDate.map { isoTimestamp($0) } ?? isoTimestamp()
        ]
        properties["hs_task_status"] = "NOT_STARTED"
        let body = makeObjectBody(
            properties: properties,
            associatedObjectID: input.associatedObjectID,
            associatedObjectType: input.associatedObjectType
        )
        return try sendSync(path: "/crm/v3/objects/tasks", method: "POST", jsonBody: body)
    }

    func updateDealStage(_ input: HubSpotUpdateDealStageInput) throws -> String {
        let body: [String: Any] = [
            "properties": [
                "dealstage": input.stageID
            ]
        ]
        return try sendSync(path: "/crm/v3/objects/deals/\(input.dealID)", method: "PATCH", jsonBody: body)
    }

    func logEmail(_ input: HubSpotLogEmailInput) throws -> String {
        let body = makeObjectBody(properties: [
            "hs_email_subject": input.subject,
            "hs_email_text": input.body,
            "hs_timestamp": isoTimestamp()
        ], associatedObjectID: input.associatedObjectID, associatedObjectType: input.associatedObjectType)
        return try sendSync(path: "/crm/v3/objects/emails", method: "POST", jsonBody: body)
    }

    private func sendSync(
        path: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) throws -> String {
        guard let accessToken = accessTokenProvider(), !accessToken.isEmpty else {
            throw NSError(domain: "HubSpotAPIClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Connect HubSpot before running HubSpot skills."
            ])
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error>!
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            guard (200...299).contains(statusCode) else {
                result = .failure(NSError(domain: "HubSpotAPIClient", code: statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "HubSpot API error (\(statusCode)): \(body)"
                ]))
                return
            }
            result = .success(body.isEmpty ? "{}" : body)
        }.resume()
        semaphore.wait()
        return try result.get()
    }

    private func makeObjectBody(
        properties: [String: Any],
        associatedObjectID: String?,
        associatedObjectType: String?
    ) -> [String: Any] {
        guard let associatedObjectID,
              let associatedObjectType,
              !associatedObjectID.isEmpty,
              !associatedObjectType.isEmpty else {
            return ["properties": properties]
        }

        return [
            "properties": properties,
            "associations": [
                [
                    "to": ["id": associatedObjectID],
                    "types": [
                        [
                            "associationCategory": "HUBSPOT_DEFINED",
                            "associationTypeId": associationTypeID(for: associatedObjectType)
                        ]
                    ]
                ]
            ]
        ]
    }

    private func associationTypeID(for objectType: String) -> Int {
        switch objectType.lowercased() {
        case "contact", "contacts": return 202
        case "company", "companies": return 190
        case "deal", "deals": return 214
        default: return 202
        }
    }

    private func isoTimestamp(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
