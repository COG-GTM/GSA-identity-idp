# Comprehensive Documentation Plan for Login.gov Identity Provider (IdP)

This document outlines a comprehensive documentation plan for the GSA-identity-idp repository, identifying gaps in current documentation, prioritizing new documentation needs, and providing a structured approach to making this complex government identity system accessible to new developers.

## Executive Summary

The Login.gov IdP is a Ruby on Rails 8.0 application serving as a federated identity provider for U.S. government agencies. While the repository has foundational documentation in the `docs/` directory, significant gaps exist in architecture documentation, developer onboarding materials, API documentation, and operations guides. This plan addresses these gaps with prioritized, actionable documentation tasks.

## Current Documentation Assessment

### Existing Documentation Files

| File | Status | Coverage | Recommended Action |
|------|--------|----------|-------------------|
| `docs/backend.md` | Good | Forms, FormResponse, Analytics, Controllers | Update with Service Objects, multi-database architecture |
| `docs/frontend.md` | Excellent | CSS, JavaScript, Components, Testing | Minor updates for new packages |
| `docs/local-development.md` | Good | Setup, testing, configuration | Add troubleshooting links, expand PIV/CAC section |
| `docs/troubleshooting.md` | Good | Common errors and fixes | Expand with more scenarios |
| `docs/mobile.md` | Good | Mobile development setup | No changes needed |
| `docs/ab-testing.md` | Good | A/B testing framework | No changes needed |
| `docs/sdk-upgrade.md` | Good | Acuant SDK upgrade process | No changes needed |
| `docs/SECURITY.md` | Minimal | High-level security overview | Expand significantly |
| `docs/attempts-api/` | Good | OpenAPI specification | Add integration guide |
| `README.md` | Minimal | Links to other docs | Expand with architecture overview |
| `CONTRIBUTING.md` | Good | PR guidelines, changelog format | Add code standards section |

### Critical Documentation Gaps

1. **Architecture Documentation**: No comprehensive system architecture documentation
2. **Identity Verification (IDV) Flow**: Progressive proofing algorithm undocumented
3. **Multi-Vendor Integration**: Vendor fallback strategy not documented
4. **Database Architecture**: Multi-database setup with read replicas undocumented
5. **CI/CD Pipeline**: GitLab CI configuration not explained
6. **API Documentation**: SAML/OIDC implementations lack developer guides
7. **Operations Runbooks**: No deployment or incident response documentation

## Documentation Plan

### Priority 1: Critical for Developer Onboarding (High Impact)

#### 1.1 System Architecture Overview
**File**: `docs/architecture/README.md`
**Effort**: 3-4 hours
**Format**: Markdown with Mermaid diagrams

**Content**:
- High-level system architecture diagram
- Core system components and their responsibilities
- Request flow from Service Provider to IdP and back
- Technology stack overview (Ruby 3.4.5, Rails 8.0, PostgreSQL, Redis, GoodJob)
- Directory structure explanation

**Diagram to include**:
```
Service Provider → Federation Layer (SAML/OIDC) → Authentication System → IDV System → Profile Management
```

#### 1.2 Identity Verification (IDV) Architecture
**File**: `docs/architecture/identity-verification.md`
**Effort**: 4-5 hours
**Format**: Markdown with flowcharts and code references

**Content**:
- IDV flow overview (Welcome → Agreement → Document Capture → SSN → Verify Info → Phone → Personal Key)
- Progressive Proofing algorithm explanation (reference `app/services/proofing/resolution/progressive_proofer.rb`)
- `Idv::Session` state management
- `ResolutionProofingJob` async processing
- `ResultAdjudicator` decision logic
- Vendor plugin architecture (AAMVA, ThreatMetrix, Phone, Resolution)

**Code references**:
- `app/services/proofing/resolution/progressive_proofer.rb`
- `app/jobs/resolution_proofing_job.rb`
- `app/services/idv/session.rb`
- `app/controllers/idv/verify_info_controller.rb`

#### 1.3 Multi-Vendor Integration Guide
**File**: `docs/architecture/vendor-integrations.md`
**Effort**: 3-4 hours
**Format**: Markdown with configuration examples

**Content**:
- Vendor overview (LexisNexis, Socure, AAMVA, ThreatMetrix, Acuant)
- Vendor selection logic and fallback strategy
- Configuration options (`idv_resolution_default_vendor`, vendor percentages)
- A/B testing vendors
- Vendor-specific error handling
- Adding new vendors

**Configuration examples from**:
- `lib/identity_config.rb` (vendor configuration options)
- `config/application.yml.default` (default values)

#### 1.4 npm Workspace and Frontend Packages Guide
**File**: `docs/frontend-packages.md`
**Effort**: 2-3 hours
**Format**: Markdown with package descriptions

**Content**:
- Overview of 45+ workspace packages in `app/javascript/packages/`
- Package categories (UI components, utilities, build tools, testing)
- How to create a new package
- Package dependency management
- Key packages deep-dive:
  - `@18f/identity-document-capture` - Document capture flow
  - `@18f/identity-webauthn` - WebAuthn authentication
  - `@18f/identity-form-steps` - Multi-step form handling
  - `@18f/identity-analytics` - Frontend analytics
  - `@18f/identity-i18n` - Internationalization

### Priority 2: Important for Development Workflow (Medium-High Impact)

#### 2.1 Database Architecture
**File**: `docs/architecture/database.md`
**Effort**: 2-3 hours
**Format**: Markdown with schema diagrams

**Content**:
- Multi-database architecture overview
- Primary database vs read replica configuration
- Worker jobs database separation (`WorkerJobApplicationRecord`)
- Key tables and relationships (users, profiles, identities, email_addresses)
- Database connection pooling
- Migration procedures for multi-database setup
- Console access with read-only mode

**Code references**:
- `config/application.rb` (database configuration)
- `db/schema.rb` (schema definition)
- `config/database.yml` (connection settings)

#### 2.2 Analytics Events System
**File**: `docs/architecture/analytics.md`
**Effort**: 2-3 hours
**Format**: Markdown with examples

**Content**:
- Analytics architecture overview
- `AnalyticsEvents` module (8,500+ lines, 500+ events)
- Event naming conventions
- Adding new analytics events
- Frontend analytics integration (`FrontendLogController`)
- YARD documentation for events
- Debugging with `make watch_events`
- A/B test bucket logging

**Code references**:
- `app/services/analytics_events.rb`
- `app/services/analytics.rb`
- `app/controllers/frontend_log_controller.rb`

#### 2.3 Background Jobs Guide
**File**: `docs/architecture/background-jobs.md`
**Effort**: 2 hours
**Format**: Markdown with job listings

**Content**:
- GoodJob configuration and setup
- Job scheduling (cron configuration in `config/initializers/job_configurations.rb`)
- Critical jobs overview:
  - `ResolutionProofingJob` - Identity proofing
  - `GpoDailyJob` - GPO letter mailing
  - `GetUspsProofingResultsJob` - USPS in-person proofing
  - Report jobs (daily, weekly, monthly)
- Job queues and priorities
- Monitoring and debugging jobs
- Adding new scheduled jobs

#### 2.4 CI/CD Pipeline Documentation
**File**: `docs/ci-cd.md`
**Effort**: 2-3 hours
**Format**: Markdown with pipeline diagrams

**Content**:
- GitLab CI pipeline overview (`.gitlab-ci.yml`)
- Pipeline stages: build → test → after_test → review → scan → deploy_eks
- Key jobs explanation:
  - `install` - Dependency installation
  - `specs` - RSpec tests (22 parallel nodes with Knapsack Pro)
  - `lint` - Code linting
  - `js_tests` - JavaScript tests
  - `build-idp-image` - Docker image building with Kaniko
  - `review-app` - Ephemeral review environments
- Caching strategy (Ruby gems, npm packages, assets)
- Deployment triggers and environments
- Debugging failed CI jobs

### Priority 3: Important for API Integration (Medium Impact)

#### 3.1 SAML 2.0 Implementation Guide
**File**: `docs/api/saml.md`
**Effort**: 3-4 hours
**Format**: Markdown with request/response examples

**Content**:
- SAML 2.0 protocol overview
- Authentication flow (AuthnRequest → Response)
- Logout flow (LogoutRequest → LogoutResponse)
- Supported bindings (HTTP-POST, HTTP-Redirect)
- Attribute mapping and release
- Service Provider configuration
- Error handling and troubleshooting

**Code references**:
- `app/controllers/saml_idp_controller.rb`
- `app/models/federated_protocols/saml.rb`
- `app/services/saml_request_validator.rb`

#### 3.2 OpenID Connect Implementation Guide
**File**: `docs/api/oidc.md`
**Effort**: 3-4 hours
**Format**: Markdown with request/response examples

**Content**:
- OIDC protocol overview
- Authorization endpoint (`/openid_connect/authorize`)
- Token endpoint (`/api/openid_connect/token`)
- UserInfo endpoint (`/api/openid_connect/userinfo`)
- Supported scopes and claims
- PKCE support
- Vectors of Trust (VoT) implementation
- Error handling

**Code references**:
- `app/controllers/openid_connect/authorization_controller.rb`
- `app/controllers/openid_connect/token_controller.rb`
- `lib/vot/parser.rb`

#### 3.3 WebAuthn Authentication Guide
**File**: `docs/api/webauthn.md`
**Effort**: 2 hours
**Format**: Markdown with code examples

**Content**:
- WebAuthn overview and supported authenticators
- COSE algorithm support (ES256, ES384, ES512, PS256, PS384, PS512, RS256)
- Enrollment flow (`enrollWebauthnDevice`)
- Authentication flow
- Platform vs cross-platform authenticators
- Resident key support
- Browser compatibility notes

**Code references**:
- `app/javascript/packages/webauthn/enroll-webauthn-device.ts`
- `app/controllers/users/webauthn_setup_controller.rb`
- `config/initializers/webauthn.rb`

#### 3.4 Attempts API Integration Guide
**File**: `docs/api/attempts-api.md`
**Effort**: 1-2 hours
**Format**: Markdown with API examples

**Content**:
- Attempts API overview
- Authentication and authorization
- Event polling endpoint
- Event acknowledgment
- Integration with existing `docs/attempts-api/openapi.yml`

### Priority 4: Operations and Security (Medium Impact)

#### 4.1 Security Architecture
**File**: `docs/security/README.md` (expand existing `docs/SECURITY.md`)
**Effort**: 3-4 hours
**Format**: Markdown with security diagrams

**Content**:
- Security architecture overview
- Encryption at rest (KMS, PII encryption)
- Encryption in transit (TLS, XML encryption)
- Rate limiting with Rack::Attack
- Session security and CSRF protection
- PII handling and storage
- Fraud detection (ThreatMetrix integration)
- Security headers configuration
- Audit logging

#### 4.2 Deployment Guide
**File**: `docs/operations/deployment.md`
**Effort**: 2-3 hours
**Format**: Markdown with checklists

**Content**:
- Deployment environments (dev, staging, production)
- Deployment process overview
- Configuration management (`app-s3-secret`)
- Database migrations in production
- Rolling deployments
- Rollback procedures
- Post-deployment verification

#### 4.3 Monitoring and Alerting
**File**: `docs/operations/monitoring.md`
**Effort**: 2 hours
**Format**: Markdown with dashboard links

**Content**:
- NewRelic APM integration
- CloudWatch dashboards
- Key metrics to monitor
- Alert configuration
- Incident response procedures
- Log analysis

### Priority 5: Code Contribution Guidelines (Lower Impact)

#### 5.1 Coding Standards
**File**: `docs/coding-standards.md`
**Effort**: 2 hours
**Format**: Markdown with examples

**Content**:
- Ruby style guide (RuboCop configuration)
- TypeScript style guide (ESLint configuration)
- Naming conventions
- File organization
- Testing requirements
- Code review checklist
- Security considerations for identity systems

#### 5.2 Testing Guide
**File**: `docs/testing.md`
**Effort**: 2-3 hours
**Format**: Markdown with examples

**Content**:
- Testing philosophy and coverage requirements
- RSpec testing patterns
- Feature/integration tests with Capybara
- JavaScript testing with Mocha and Testing Library
- Test helpers and factories
- Running tests locally and in CI
- Debugging test failures

## Proposed Documentation Structure

```
docs/
├── README.md                          # Documentation index
├── DOCUMENTATION_PLAN.md              # This plan (remove after implementation)
├── architecture/
│   ├── README.md                      # System architecture overview
│   ├── identity-verification.md       # IDV flow and progressive proofing
│   ├── vendor-integrations.md         # Multi-vendor integration guide
│   ├── database.md                    # Database architecture
│   ├── analytics.md                   # Analytics events system
│   └── background-jobs.md             # GoodJob and scheduled tasks
├── api/
│   ├── saml.md                        # SAML 2.0 implementation
│   ├── oidc.md                        # OpenID Connect implementation
│   ├── webauthn.md                    # WebAuthn authentication
│   └── attempts-api.md                # Attempts API guide
├── operations/
│   ├── deployment.md                  # Deployment procedures
│   └── monitoring.md                  # Monitoring and alerting
├── security/
│   └── README.md                      # Security architecture (expanded)
├── frontend.md                        # Existing (minor updates)
├── frontend-packages.md               # NEW: npm workspace guide
├── backend.md                         # Existing (updates needed)
├── local-development.md               # Existing (minor updates)
├── troubleshooting.md                 # Existing (expand)
├── mobile.md                          # Existing (no changes)
├── ab-testing.md                      # Existing (no changes)
├── sdk-upgrade.md                     # Existing (no changes)
├── ci-cd.md                           # NEW: CI/CD pipeline
├── coding-standards.md                # NEW: Coding standards
├── testing.md                         # NEW: Testing guide
└── attempts-api/                      # Existing OpenAPI spec
    ├── openapi.yml
    ├── paths/
    └── schemas/
```

## Implementation Timeline

### Phase 1: Critical Documentation (Weeks 1-2)
- System Architecture Overview (1.1)
- Identity Verification Architecture (1.2)
- Multi-Vendor Integration Guide (1.3)
- npm Workspace Guide (1.4)

**Estimated effort**: 12-16 hours

### Phase 2: Development Workflow (Weeks 3-4)
- Database Architecture (2.1)
- Analytics Events System (2.2)
- Background Jobs Guide (2.3)
- CI/CD Pipeline Documentation (2.4)

**Estimated effort**: 8-11 hours

### Phase 3: API Documentation (Weeks 5-6)
- SAML 2.0 Implementation Guide (3.1)
- OpenID Connect Implementation Guide (3.2)
- WebAuthn Authentication Guide (3.3)
- Attempts API Integration Guide (3.4)

**Estimated effort**: 9-12 hours

### Phase 4: Operations and Standards (Weeks 7-8)
- Security Architecture (4.1)
- Deployment Guide (4.2)
- Monitoring and Alerting (4.3)
- Coding Standards (5.1)
- Testing Guide (5.2)

**Estimated effort**: 11-14 hours

**Total estimated effort**: 40-53 hours

## Documentation Standards

### Format Guidelines

1. **Markdown**: All documentation should be written in GitHub-flavored Markdown
2. **Diagrams**: Use Mermaid for flowcharts and sequence diagrams (renders in GitHub)
3. **Code Examples**: Include relevant code snippets with syntax highlighting
4. **Cross-references**: Link to related documentation and source code files
5. **Versioning**: Note when documentation was last updated

### Content Guidelines

1. **Audience**: Write for developers new to the codebase
2. **Context**: Explain "why" before "how"
3. **Examples**: Provide practical, working examples
4. **Accuracy**: Keep documentation synchronized with code changes
5. **Accessibility**: Use clear, concise language

### Maintenance

1. **Review cycle**: Quarterly review of all documentation
2. **PR requirements**: Documentation updates required for significant code changes
3. **Ownership**: Assign documentation owners for each section
4. **Feedback**: Include feedback mechanism for documentation improvements

## Success Metrics

1. **Onboarding time**: Reduce new developer onboarding time by 50%
2. **Support requests**: Decrease internal documentation-related questions by 40%
3. **Coverage**: Achieve 100% coverage of critical systems
4. **Freshness**: All documentation updated within last 6 months

## Appendix: Existing Documentation Updates

### Updates to `docs/backend.md`

Add sections for:
- Service Objects pattern and usage
- Multi-database architecture reference
- Rate limiting configuration
- Link to new architecture documentation

### Updates to `docs/frontend.md`

Add sections for:
- Link to new `frontend-packages.md`
- Update package count (45+ packages)
- Add ViewComponent Lookbook reference

### Updates to `README.md`

Expand to include:
- Architecture overview section
- Quick links to key documentation
- Technology stack summary
- Link to documentation index

### Updates to `CONTRIBUTING.md`

Add sections for:
- Link to coding standards
- Security considerations for PRs
- Testing requirements
- Documentation requirements for new features
