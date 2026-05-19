//
//  MeetingDemoData.swift
//  leanring-buddy
//
//  Realistic founder/investor meeting transcript used for demo mode.
//

import Foundation

enum MeetingDemoData {
    static let transcript = """
    Meeting: Yaven x Benchmark Capital — Seed Partnership Discussion
    Date: Monday, May 19 2026
    Attendees: Bettina Sosa (Yaven, CEO), Nick Chen (Yaven, CTO), Maya Goldberg (Benchmark, Partner)
    Duration: 45 minutes

    Maya: Thanks for making the trip. I've been following what you're building since the ProductHunt launch. Let's start with where you are today.

    Bettina: We're building the AI layer for the working day — a macOS menu-bar tool that understands your context and acts across your tools without app switching. The pitch is simple: you never leave your flow. You press a hotkey, describe what needs to happen, and Yaven does it across Gmail, Notion, HubSpot, Calendar.

    Nick: Under the hood we intercept screen context only on demand — nothing continuous. The model sees what the user is focused on, routes to the right Composio integration, and executes in the background. We've shipped Gmail, Notion, HubSpot, Calendar, and Granola integrations. The whole stack is local-first with a Cloudflare Worker proxying the AI calls.

    Maya: What's the wedge? Every AI assistant says context-aware these days.

    Bettina: The wedge is friction. We live in the notch — zero switching cost. No new tab, no new app. Press Space+Y and you're talking to Yaven. We're already running our own sales workflow on it: one command logs a call to HubSpot, drafts the follow-up email, and creates the Notion entry. Steve — our first paying user — cut his end-of-day admin time by 40% in six weeks.

    Maya: Traction? Are people actually paying?

    Bettina: Twelve design partners at $49 per month. All inbound from LinkedIn content — we spend nothing on ads. NPS from the cohort is 72. Steve is actively referring portfolio founders. We project 25 paying users by August with no new spend.

    Maya: The cohort size is small. What's the go-to-market after the design partners?

    Bettina: Founder-led for the first fifty. Then a PLG motion — each time Yaven executes a workflow it creates an artifact: a Notion page, a HubSpot note. Those artifacts tag Yaven, creating organic discovery. Long term, we think the wedge is the operator persona: chiefs of staff, BizOps, sales leaders who live in five tools at once.

    Maya: What do you need?

    Bettina: Two million seed. Eighteen months of runway covers: one, reach 25 paying design partners by August; two, ship the integrations roadmap — Slack, Linear, Figma; three, hire one senior backend engineer to productize the workflow runtime.

    Maya: I like the category but I want to stress-test distribution. How do you get to 100 customers?

    Nick: The artifact loop is the answer. Every Notion page and HubSpot note we create has a generated-with-Yaven footer. That's free distribution into the tools operators already live in.

    Maya: That's interesting. Okay. What's the next concrete step you need from me?

    Bettina: Ideally a term sheet. But even a follow-up with your technical partner for a product deep dive moves things forward for us.

    Maya: I'll loop in James Park, our technical partner. He'll want to see the architecture and the integration pipeline. Can you have a one-pager and technical diligence deck ready by Thursday?

    Nick: We'll have it Wednesday so you have time to review before James's calendar slot.

    Maya: Good. I'll also introduce you to two portfolio founders — Clara at Orbit and David at Katch — who are exactly your target persona. They can give real feedback and may want to be design partners themselves.

    Bettina: That would be invaluable, thank you.

    Maya: One more question. What's the moat when a well-funded competitor copies the form factor?

    Bettina: Day-one data moat. Every user builds a private context graph — their workflows, tools, and patterns stay local. The more they use it, the smarter the routing becomes. A cold-start competitor can't replicate six months of a user's working patterns.

    Maya: Fair. Alright — James will reach out by Wednesday. Send me the deck when it's ready. Good conversation, both of you.

    Bettina: Thank you, Maya. We'll follow up today.
    """
}
