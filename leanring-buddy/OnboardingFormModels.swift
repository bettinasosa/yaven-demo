//
//  OnboardingFormModels.swift
//  leanring-buddy
//
//  Static config and async tool-catalog loading for the form onboarding flow.
//  Ported role / tool / time-sink mappings from the Yaven website blueprint panel.
//

import Foundation

// MARK: - Composio Tool

struct ComposioTool: Codable, Identifiable, Equatable {
    let key: String
    let name: String
    let logo: String
    var id: String { key }
}

private struct ToolCatalogResponse: Codable {
    let tools: [ComposioTool]
}

enum ToolCatalog {
    #if DEBUG
    static let workerBaseURL = "http://localhost:8787"
    #else
    static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    static func load() async -> [ComposioTool] {
        guard let url = URL(string: "\(workerBaseURL)/tools") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        guard let response = try? JSONDecoder().decode(ToolCatalogResponse.self, from: data) else { return [] }
        return response.tools.map { tool in
            // Strip MCP branding — users don't know what MCP means.
            var name = tool.name
            if name.hasSuffix(" MCP Server") { name = String(name.dropLast(" MCP Server".count)) }
            if name.hasSuffix(" MCP") { name = String(name.dropLast(" MCP".count)) }
            if name.hasPrefix("MCP ") { name = String(name.dropFirst("MCP ".count)) }
            name = name.trimmingCharacters(in: .whitespaces)
            return ComposioTool(key: tool.key, name: name, logo: tool.logo)
        }
    }
}

// MARK: - Role List

let onboardingRoles: [String] = [
    "Founder", "Freelancer", "Consultant", "Creator", "Operator",
    "Sales / BD", "Marketing", "Product", "Engineering", "Recruiting",
    "Customer Success", "Finance / Ops", "Executive Assistant",
    "Research", "Student", "Other"
]

// MARK: - Tools by Role (used to surface suggested tools first)

let toolNamesByRole: [String: [String]] = [
    "Founder": ["Notion", "Linear", "HubSpot", "Slack", "Gmail", "Zoom", "Google Drive",
                "Stripe", "QuickBooks", "Calendly", "Loom", "Airtable", "Granola", "LinkedIn"],
    "Freelancer": ["Notion", "Gmail", "Slack", "Figma", "Canva", "Google Drive",
                   "Calendly", "Stripe", "Toggl", "Harvest", "Zoom"],
    "Consultant": ["Notion", "Google Slides", "Excel", "Gmail", "Zoom", "Slack",
                   "HubSpot", "Calendly", "Loom", "Miro"],
    "Creator": ["Notion", "Canva", "CapCut", "Premiere Pro", "ChatGPT",
                "TikTok Studio", "YouTube Studio", "Beehiiv", "ConvertKit", "Slack"],
    "Operator": ["Notion", "Airtable", "Slack", "Gmail", "Google Sheets",
                 "Zapier", "Linear", "Asana", "ClickUp", "Loom"],
    "Sales / BD": ["Apollo", "Clay", "HubSpot", "Salesforce", "LinkedIn", "Instantly",
                   "Granola", "Notion", "Slack", "Gmail", "Calendly", "Zoom"],
    "Marketing": ["HubSpot", "Mailchimp", "Klaviyo", "Canva", "Figma", "Google Analytics",
                  "Meta Ads", "Notion", "Slack", "Buffer", "Loom", "Google Sheets"],
    "Product": ["Notion", "Linear", "Jira", "Figma", "Slack", "Zoom",
                "Mixpanel", "Amplitude", "Loom", "Confluence", "Miro"],
    "Engineering": ["GitHub", "Linear", "Jira", "Slack", "Notion", "Figma",
                    "VS Code", "Datadog", "Sentry", "Confluence", "Zoom"],
    "Recruiting": ["LinkedIn", "Greenhouse", "Lever", "Ashby", "Notion", "Slack",
                   "Gmail", "Calendly", "Workable", "Loom", "Google Sheets"],
    "Customer Success": ["Intercom", "Zendesk", "HubSpot", "Salesforce", "Slack",
                         "Notion", "Zoom", "Gainsight", "Calendly"],
    "Finance / Ops": ["QuickBooks", "Xero", "Stripe", "Notion", "Google Sheets",
                      "Excel", "Slack", "Gmail", "Airtable", "Bill.com"],
    "Executive Assistant": ["Gmail", "Google Calendar", "Notion", "Slack", "Zoom",
                            "Calendly", "Asana", "Google Drive", "Loom", "Trello", "ClickUp"],
    "Research": ["Notion", "Google Scholar", "Zotero", "Obsidian", "Excel",
                 "Google Sheets", "Slack", "Gmail", "Zoom", "Miro", "Airtable"],
    "Student": ["Notion", "Google Docs", "Google Scholar", "Zotero", "Obsidian",
                "ChatGPT", "Gmail", "Zoom", "Slack", "Anki"],
    "Other": ["Gmail", "Slack", "Notion", "Google Drive", "Google Sheets",
              "Excel", "Zoom", "Asana", "Trello", "ClickUp", "Airtable", "Loom", "ChatGPT"]
]

// MARK: - Time Sinks by Role

let timeSinksByRole: [String: [String]] = [
    "Founder": [
        "Chasing invoices", "Writing investor updates", "Answering intro emails",
        "Writing job descriptions", "Tidying meeting notes", "Summarising docs for the team",
        "Scheduling introductions", "Weekly status updates"
    ],
    "Freelancer": [
        "Writing proposals and SOWs", "Chasing client feedback",
        "Sending invoices and payment reminders", "Updating time trackers",
        "Onboarding new clients", "Writing project status updates"
    ],
    "Consultant": [
        "Writing meeting recaps", "Building slide decks", "Chasing client sign-offs",
        "Writing status reports", "Preparing agendas", "Summarising research"
    ],
    "Creator": [
        "Repurposing long content into short clips", "Writing email newsletters",
        "Scheduling posts", "Responding to comments",
        "Writing video descriptions and tags", "Compiling analytics reports"
    ],
    "Operator": [
        "Pulling data across tools into one place", "Writing weekly team updates",
        "Updating trackers after meetings", "Chasing people for status",
        "Building leadership reports", "Managing recurring tasks manually"
    ],
    "Sales / BD": [
        "Copy-pasting outreach to LinkedIn", "Writing personalised follow-up emails",
        "Logging call notes to CRM", "Building prospect lists from scratch",
        "Sending connection requests", "Updating deal stages",
        "Writing cold email sequences", "Compiling the weekly pipeline report",
        "Scheduling follow-up meetings", "Enriching contact data manually"
    ],
    "Marketing": [
        "Writing weekly performance reports", "Scheduling and posting social content",
        "Pulling analytics for decks", "Briefing freelancers",
        "Updating spreadsheets with campaign data", "Repurposing content across channels",
        "Writing first-draft copy", "Chasing approvals"
    ],
    "Product": [
        "Writing user story tickets", "Summarising customer feedback",
        "Meeting notes and recaps", "Weekly product updates",
        "Updating roadmaps across tools", "Writing release notes"
    ],
    "Engineering": [
        "Writing PR descriptions and release notes", "Copying tickets between tools",
        "Writing standup updates", "Documenting API endpoints",
        "Responding to repeated Slack questions"
    ],
    "Recruiting": [
        "Writing personalised candidate outreach", "Updating candidate status in ATS",
        "Scheduling interviews", "Summarising interview notes",
        "Writing job descriptions", "Sending offer or rejection emails"
    ],
    "Customer Success": [
        "Follow-up emails after calls", "Updating health scores in CRM",
        "Building QBR decks", "Logging support tickets",
        "Summarising call notes and action items", "Sending renewal reminders"
    ],
    "Finance / Ops": [
        "Reconciling transactions", "Chasing approvals", "Writing expense reports",
        "Pulling monthly financials", "Updating spreadsheets", "Sending payment reminders"
    ],
    "Executive Assistant": [
        "Scheduling and rescheduling meetings", "Managing email triage",
        "Writing meeting recaps", "Coordinating travel",
        "Following up on action items", "Preparing briefing docs"
    ],
    "Research": [
        "Summarising papers and articles", "Pulling quotes and citations into notes",
        "Writing literature review sections", "Transcribing interviews",
        "Building data collection trackers", "Writing meeting recaps from calls"
    ],
    "Student": [
        "Taking and tidying lecture notes", "Summarising readings and papers",
        "Writing essay drafts", "Organising references and citations",
        "Building revision notes from scratch", "Tracking deadlines and assignments",
        "Emailing tutors and professors"
    ],
    "Other": [
        "Copy-pasting information across tools", "Drafting reports from research",
        "Writing repetitive emails", "Chasing people for updates",
        "Manually updating spreadsheets", "Taking and tidying meeting notes",
        "Building decks from scratch", "Logging the same thing in multiple places"
    ]
]
