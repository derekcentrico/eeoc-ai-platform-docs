Subject: ADR Portal Demo Environment - Feature Overview and Testing Guide

Team,

The ADR Portal demo environment is ready for review. Test mode is enabled with seeded cases. Below is a walkthrough of the application's features and how to navigate them. Each feature area is its own module and can be evaluated independently.

**Login:** Use your EEOC Entra ID credentials at the demo URL. Your account has been provisioned with admin access so you can see all modules and switch between roles during testing. If you want to see the Login.gov flow for external parties, let me know and I will add you to the Login.gov sandbox.

---

**Getting Started: Role Switching and Impersonation**

After login, go to the Admin Dashboard. You will see two options at the top:

- **Quick Role Switch** lets you view the portal as a mediator, supervisor, or director. Your real identity is preserved so Graph API features (email, calendar, Teams) still work with your mailbox.
- **Demo Persona Switcher** lets you impersonate a seeded test persona with a full identity switch. Use this to test the external party view (what a charging party or respondent sees) without needing a separate Login.gov account.

Try switching to Mediator first to see the core case workflow, then switch to Supervisor/Director to see the management views.

---

**Module 1: Case Dashboard (Mediator View)**

Switch to Mediator role. You land on the case dashboard showing your assigned mediation cases. Each case card shows status, parties, next scheduled session, and unread message count. Click into any seeded case to open the full case view.

**Module 2: Case Detail and Real-Time Chat**

Inside a case, you see tabbed sections for case information, parties, documents, chat, scheduling, and the settlement agreement workspace. The chat is separated by channel (main, complainant caucus, agency/respondent caucus). Messages appear in real time. Try posting a message in the main channel, then switch to a caucus channel to verify isolation. The other party cannot see caucus messages.

**Module 3: AI Assistant (In-Case)**

Within a case, open the AI chat. The assistant has context about the case and can help draft settlement terms, summarize case facts, and suggest next steps. It uses Azure OpenAI and all interactions are audit-logged. Try asking it to draft settlement language or summarize the dispute. Note that AI output always requires your review before it goes anywhere.

**Module 4: Settlement Agreement Drafting**

In the Agreement tab of a case, you can start a new settlement draft. The system pulls a DOCX template, fills in party names and case details, and lets you edit in a rich text editor. You can also ask the AI to generate initial terms. Versions are tracked. Once finalized, the agreement can be sent for e-signature if that feature is enabled.

**Module 5: Scheduling and Calendar**

Go to your Settings page (gear icon) to configure your availability, work hours, time zone, and meeting preferences. Then inside a case, go to the Scheduling tab. You can propose meeting times, create polls for party availability, and schedule sessions. Calendar events sync to Outlook via Microsoft Graph. To test this properly, create your own case (instructions below) and schedule a real session so you can see the calendar invite arrive in your Outlook.

**Module 6: Management Dashboard (Supervisor/Director View)**

Switch to Supervisor or Director role. The navigation changes to show My Team, Reports, Calendar, and Schedules. The team view shows all mediators under your span of control with their active case counts, settlement rates, and workload. You can click into any mediator to see their cases. Directors see the full office subtree.

**Module 7: Reports and Analytics**

From the Reports tab (supervisor/director/admin), you can filter by sector (OFS/OFP), office, team, mediator, and date range. Six charts show mediator workload, settlement rates, case activity over time, cases by office, meeting activity, and total caseload. Reports export to CSV or Excel. Model drift and AI reliance analytics are also available here.

**Module 8: Office and Staff Management (Admin)**

Switch back to Admin. Go to Offices to see the organizational hierarchy. You can create, edit, reparent, merge, and deactivate offices. Go to Staff and Users to add mediators, change roles, reassign offices, and manage supervisor relationships. You can also bulk-import staff from Entra ID security groups with configurable mapping rules.

**Module 9: FOIA Export and Records Disposition (Admin)**

Go to FOIA/NARA in the admin nav. You can export all AI audit records and chat logs for any case as a signed ZIP file with chain-of-custody metadata. The disposition queue shows cases past their retention window. Litigation holds are checked before any disposition proceeds.

**Module 10: Audit Logs (Admin)**

Go to the audit log viewer to search all system activity by case, user, action type, and date range. Each case also has an Activity tab showing a full timeline of every action taken on that case.

---

**Creating Your Own Test Cases**

To fully test scheduling, calendar integration, and the party experience:

1. Switch to Admin role
2. Go to Cases and create a new case
3. Assign yourself as the mediator (use Quick Role Switch afterward to act as that mediator)
4. Add test party email addresses for the complainant and respondent (use real @eeoc.gov addresses if you want to receive the email notifications and calendar invites)
5. Switch to Mediator role and open your new case
6. Try scheduling a session, sending a message, drafting a settlement, and using the AI assistant

This gives you the complete workflow from case creation through scheduling and settlement. The seeded demo cases are useful for browsing, but creating your own is the best way to test the interactive features.

---

Let me know if you have questions or need your account permissions adjusted. Happy to walk through any of this on a call.

Derek
