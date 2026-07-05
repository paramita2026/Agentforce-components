# Agentforce Components — Salesforce Health Cloud

> Custom **Agentforce** components built for an aged care / NDIS organisation on **Salesforce Health Cloud**. Includes an Invocable Apex action and four Flows that power an AI-assisted support agent — handling customer identity verification, profile retrieval, task creation, and appointment monitoring.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Business Context](#business-context)
- [Solution Design](#solution-design)
- [Components](#components)
- [Data Model](#data-model)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Deployment Guide](#deployment-guide)

---

## Project Overview

This project delivers the backend building blocks of an **Agentforce AI agent** for an aged care / NDIS support organisation. The agent handles after-hours customer interactions — authenticating callers, retrieving their care profile, logging tasks, and monitoring upcoming appointments.

| Component | Type | Purpose |
|-----------|------|---------|
| `AgentCustomerActions` | Apex Invocable Action | Retrieves a verified customer's (Contact) profile by Id or email |
| `Send Email with Verification Code` | AutoLaunched Flow | Generates a one-time code and emails it to the customer to prove identity |
| `Verify Code` | AutoLaunched Flow | Validates the code entered by the customer; returns verified status |
| `Create New Task` | Screen Flow | Allows the agent/coordinator to log a Task linked to a record, assignable to a user or the After Hours Support queue |
| `Appointment Notifications within 48 hours` | Scheduled Flow | Runs daily to retrieve upcoming MAICA appointments within the next 48 hours |

---

## Business Context

Aged care and NDIS organisations receive a high volume of after-hours calls from clients, family members, and coordinators. An **Agentforce AI agent** (built on Salesforce's Einstein Copilot / Service Cloud platform) handles these interactions by:

1. **Verifying the caller's identity** before sharing any personal or care-related information
2. **Retrieving the client's profile** from the Salesforce Contact record
3. **Logging tasks** so coordinators are notified of any actions raised during the AI conversation
4. **Monitoring upcoming appointments** so the agent can proactively notify relevant parties

The verification flows override Salesforce's standard Service Copilot templates (`SvcCopilotTmpl__SendVerificationCode` and `SvcCopilotTmpl__VerifyCode`) to support **Contact-based authentication** — matching on `Contact.Email` rather than the default User-based lookup, which suits organisations where clients are stored as Contacts rather than licensed Salesforce users.

---

## Solution Design

```
┌───────────────────────────────────────────────────────────────────────┐
│                     Agentforce AI Agent                               │
│             (Einstein Copilot / Service Cloud Agent)                  │
│                                                                       │
│  Customer: "Hi, I need help with my appointment"                      │
│                          │                                            │
│              ┌───────────▼────────────┐                               │
│              │  STEP 1: Verify        │  Agent asks for email         │
│              │  Identity              │                               │
│              └───────────┬────────────┘                               │
│                          │                                            │
│          ┌───────────────┼────────────────┐                           │
│          ▼               ▼                ▼                           │
│  ┌───────────────┐ ┌──────────────┐                                   │
│  │ Send Email    │ │ Verify Code  │  Flow pair: generate code →       │
│  │ with Verif.   │ │ Flow         │  email → customer enters code →   │
│  │ Code Flow     │ │              │  validate → isVerified=true/false │
│  └───────┬───────┘ └──────┬───────┘                                   │
│          │                │                                           │
│          └───────┬─────────┘                                          │
│                  │  isVerified = true                                 │
│                  ▼                                                     │
│        ┌─────────────────────┐                                        │
│        │  STEP 2: Get        │  Apex Invocable Action                 │
│        │  Customer Profile   │  AgentCustomerActions.invoke()         │
│        │  (AgentCustomer     │  Input: verifiedCustomerId OR email    │
│        │   Actions)          │  Output: name, phone, status, level,  │
│        └─────────┬───────────┘          accountId, customerJson      │
│                  │                                                     │
│          ┌───────┴────────┐                                           │
│          ▼                ▼                                           │
│  ┌──────────────┐  ┌──────────────────────────┐                      │
│  │ STEP 3:      │  │ STEP 4 (Background):      │                     │
│  │ Create New   │  │ Appointment Notifications │                     │
│  │ Task Flow    │  │ within 48 hours Flow      │                     │
│  │ (if needed)  │  │ (Scheduled — runs daily)  │                     │
│  └──────────────┘  └──────────────────────────┘                      │
└───────────────────────────────────────────────────────────────────────┘
         │                          │
         ▼                          ▼
┌─────────────────┐    ┌──────────────────────────────────────┐
│  Salesforce     │    │  Salesforce Health Cloud +           │
│  Contact Object │    │  MAICA Package Data                  │
│  ─────────────  │    │  ─────────────────────────────────── │
│  Id, Email      │    │  maica_cc__Appointment__c            │
│  FirstName      │    │  maica_cc__Scheduled_Start__c        │
│  LastName       │    │                                      │
│  Phone          │    │  Task (standard object)              │
│  AccountId      │    │  Subject, Description, Priority      │
│  Status__c      │    │  OwnerId, WhatId                     │
│  Level__c       │    └──────────────────────────────────────┘
│  Favourite_     │
│  Cuisine__c     │
└─────────────────┘
```

### Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Override `SvcCopilotTmpl__SendVerificationCode` | Standard template looks up Users; this org authenticates Contacts (clients) — override changes the lookup to `Contact.Email` |
| Override `SvcCopilotTmpl__VerifyCode` | Paired with the Send flow override to ensure the same `authenticationKey` lifecycle is used end-to-end |
| Dynamic field resolution in `AgentCustomerActions` | Custom fields (Status, Level, Cuisine) vary by org — using `fieldMap.containsKey()` at runtime means the action is portable across orgs without changing code |
| `@InvocableMethod` on Apex (not `@AuraEnabled`) | Invocable methods integrate natively with Agentforce agent actions and Flow — no LWC or API call needed |
| `with sharing` on Apex | Ensures the agent only returns Contact data the running user's profile is permitted to see |
| Dual input (Id OR email) on `AgentCustomerActions` | Early in a conversation the agent has only the email; after verification it has the Contact Id — supports both stages |
| `Create New Task` assigns to "After Hours Support queue" | Tasks raised during after-hours AI sessions are routed to the dedicated support queue for human follow-up next business day |

---

## Components

### 1. `AgentCustomerActions` — Apex Invocable Action

**Purpose:** Retrieve a verified customer's Contact profile for use by the Agentforce agent in subsequent conversation turns.

**Inputs:**

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `verifiedCustomerId` | String | Either/or | Salesforce Contact Id of the verified customer |
| `customerEmail` | String | Either/or | Contact email address (used when Id is not yet known) |

**Outputs:**

| Variable | Type | Description |
|----------|------|-------------|
| `success` | Boolean | True when the action executed without error |
| `found` | Boolean | True when a matching Contact was found |
| `message` | String | Human-readable status (e.g. "OK" or error description) |
| `verifiedCustomerId` | String | Contact Id (echoed back for downstream actions) |
| `accountId` | String | Associated Account Id |
| `firstName` | String | Customer first name |
| `lastName` | String | Customer last name |
| `customer` | CustomerDetails | Full DTO with all fields including optional custom fields |
| `customerJson` | String | JSON-serialized version of customer DTO |

**Dynamic field resolution:** The action probes the Contact field map at runtime for optional org-specific fields:
- Status: `Status__c` → `Contact_Status__c` → `Customer_Status__c` (first match)
- Level/Tier: `Level__c` → `Customer_Level__c` (first match)
- Favourite Cuisine: `Favourite_Cuisine__c` → `Favorite_Cuisine__c` → `FavouriteCuisine__c` → `FavoriteCuisine__c` (first match)

---

### 2. `Send Email with Verification Code` — AutoLaunched Flow

**Purpose:** Prove the identity of the caller before the agent shares any personal data.

**Flow steps:**
1. Look up Contact by the provided email address
2. Decision: does a Contact with that email exist?
3. If yes → call `generateVerificationCode` system action → get `verificationCode` + `authenticationKey`
4. Send email to the Contact with subject "Your Chatbot Verification Code" containing the code
5. Output `authenticationKey` (passed to Verify Code flow) and `verificationCode`

**Inputs:** `customerToVerify` (email string)
**Outputs:** `verificationCode`, `authenticationKey`, `customerId`, `customerType`, `verificationMessage`

> Overrides Salesforce standard template: `SvcCopilotTmpl__SendVerificationCode`

---

### 3. `Verify Code` — AutoLaunched Flow

**Purpose:** Validate the one-time code entered by the customer in the chat session.

**Flow steps:**
1. Call `verifyCustomerCode` system action with `customerCode` + `authenticationKey`
2. Decision: `isVerified = true`?
3. If yes → set `isVerified = true`, carry forward `customerId` and `customerType`
4. If no → set `isVerified = false`, clear customer identifiers, return error message

**Inputs:** `customerCode`, `authenticationKey`, `customerId`, `customerType`
**Outputs:** `isVerified` (Boolean), `messageAfterVerification`, `customerId`, `customerType`

> Overrides Salesforce standard template: `SvcCopilotTmpl__VerifyCode`

---

### 4. `Create New Task` — Screen Flow

**Purpose:** Allow the AI agent or coordinator to log a follow-up Task directly from the agent conversation.

**Flow steps:**
1. Screen — Task Record Creation form:
   - **Title** (required text input)
   - **Description** (large text area)
   - **Task Priority** (picklist — High / Normal / Low)
   - **Assigned To** (dropdown — all active Users OR "After Hours Support queue")
2. Create Task record linked to the triggering record via `WhatId`
3. Screen — Success confirmation message

**Input:** `recordId` (the Salesforce record the task is linked to)
**Output:** `TaskId` (Id of the newly created Task)

---

### 5. `Appointment Notifications within 48 hours` — Scheduled Flow

**Purpose:** Daily automated check of upcoming MAICA appointments to support proactive notifications.

**Schedule:** Runs daily at midnight
**Logic:** Retrieves the first `maica_cc__Appointment__c` record where `Scheduled_Start__c <= (TODAY - 2 days)`

> Status: Draft — intended as the foundation for a notification/alert extension.

---

## Data Model

| Object | Fields Used | Purpose |
|--------|-------------|---------|
| `Contact` | `Id`, `Email`, `FirstName`, `LastName`, `Phone`, `AccountId`, `Status__c`, `Level__c`, `Favourite_Cuisine__c` | Customer identity and profile |
| `Task` | `Subject`, `Description`, `Priority`, `OwnerId`, `WhatId` | Follow-up task logging |
| `maica_cc__Appointment__c` | `maica_cc__Scheduled_Start__c` | Upcoming appointment monitoring (MAICA package) |
| `Group` | `Id`, `Name`, `Type` | "After Hours Support queue" assignment target for Tasks |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| AI Agent Platform | Salesforce Agentforce (Einstein Copilot / Service Cloud) |
| Agent Actions | Apex `@InvocableMethod` |
| Identity Verification | Salesforce `generateVerificationCode` + `verifyCustomerCode` system actions |
| Automation | Salesforce Flows (AutoLaunched, Screen, Scheduled) |
| Template Overrides | `SvcCopilotTmpl__SendVerificationCode`, `SvcCopilotTmpl__VerifyCode` |
| Platform | Salesforce Health Cloud, MAICA managed package (`maica_cc`) |
| API Version | v64.0 – v67.0 |
| Dev Tooling | Salesforce CLI (`sf`), VS Code + Salesforce Extension Pack |
| Version Control | Git / GitHub |

---

## Project Structure

```
force-app/main/default/
│
├── classes/
│   ├── AgentCustomerActions.cls              # Invocable Apex action — get customer profile
│   └── AgentCustomerActions.cls-meta.xml
│
└── flows/
    ├── Send_Email_with_Verification_Code.flow-meta.xml   # Step 1: generate + email OTP
    ├── Verify_Code.flow-meta.xml                         # Step 2: validate OTP → isVerified
    ├── Create_New_Task.flow-meta.xml                     # Screen flow: log task from agent
    └── Appointment_Notifications_within_48_hours.flow-meta.xml  # Scheduled: upcoming appointments
```

---

## Deployment Guide

### Prerequisites
- Salesforce CLI installed (`sf --version`)
- Authenticated org with Health Cloud, Agentforce / Einstein Copilot, and Experience Cloud enabled
- MAICA managed package (`maica_cc`) installed (required for the Appointment Notifications flow)
- "After Hours Support queue" (`Group` record of type Queue) created in the org

### Steps

**1. Clone the repository**
```bash
git clone https://github.com/paramita2026/Agentforce-components.git
cd Agentforce-components
```

**2. Authenticate your org**
```bash
sf org login web --alias myOrg
```

**3. Deploy the Apex action**
```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/AgentCustomerActions.cls \
  --target-org myOrg
```

**4. Deploy the Flows**
```bash
sf project deploy start \
  --source-dir force-app/main/default/flows \
  --target-org myOrg
```

**5. Wire up agent actions in Agentforce**
- Go to **Setup → Agentforce Agents** → open your agent
- Add **Get Customer Profile** (`AgentCustomerActions`) as an agent action
- Confirm **Send Email with Verification Code** and **Verify Code** are listed under agent authentication actions (they override the standard templates automatically)
- Add **Create New Task** as an agent action for task logging

---

## Author

**Paramita Bhattacharya**  
GitHub: [@paramita2026](https://github.com/paramita2026)
