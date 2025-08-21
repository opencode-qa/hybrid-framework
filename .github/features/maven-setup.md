---
title: "🎯 v0.0.0 - Initial Maven Setup"
assignees: Anuj-Patiyal
reviewers: opencode-qa
milestone: v0.0.0
linked_issue: 1
labels: automation, setup, dependencies, maven
---

# 🎯 feat: Maven Initial Project Configuration (`v0.0.0`)

This PR introduces the initial setup for the **Java Selenium Hybrid Automation Framework**, laying the groundwork for a scalable and maintainable UI automation solution. It includes Maven project initialization, core dependencies, essential plugins, and directory scaffolding.


## 📂 Files Introduced or Modified
```txt
📦 java-selenium-hybrid-framework/
├── 📄 pom.xml              # Maven dependencies and plugins (🆕)
├── 📄 .gitignore           # Standard ignores for Java/Maven (🆕)
├── 📄 LICENSE              # MIT License (✔ Existing)
└── 📄 README.md            # Project overview and setup guide (🆕)
```


## 🧩 Key Features Introduced
- ✅ Maven Project Initialization
- ✅ Dependencies added in pom.xml:
  - [x] Selenium Java `4.34.0`
  - [x] TestNG `7.11.0`
- ✅ Plugins Configured:
  - [x] Maven Compiler Plugin `3.14.0` (**Java `21`**)
  - [x] Maven Clean Plugin `3.5.0`
- ✅ .gitignore configured for:
  - [x] target/, logs/, .idea/, etc.
- ✅ Project Directory Structure Scaffolding:
  - [x] src/main/java/
  - [x] src/test/java/
- ✅ Professional README.md with:
  - [x] Overview
  - [x] Tech Stack
  - [x] Features
  - [x] Project Structure
  - [x] Roadmap
  - [x] Author Info & License
- ✅ Tested Scenarios



## Scenario	Status
- [x] mvn clean executed successfully	✅
- [x] All dependencies resolved correctly	✅
- [x] Project imports in IDE without error	✅



## 🛠️ How to Verify
1. **Clone the repository:**
```bash
git clone https://github.com/your-username/java-selenium-hybrid-framework.git
cd java-selenium-hybrid-framework
```
2. **Run Maven clean build:**
```bash
    mvn clean install
```
3. **Open in your IDE and verify no build errors in structure**


## 🔗 Related Milestone

- 📍 Milestone: `v0.0.0` – Maven Initial Setup
- 🛠️ Source Branch: **`feature/maven-setup`**
- 🎯 Target Branch: **`dev`**


## Related Issues:
- Related to #1 – Maven initial setup



## 🔀 Merged PRs

- ✅ [#2](https://github.com/Anuj-Kumar-QA/hybrid-framework/pull/2) – `feature/maven-setup → dev`: Maven Initial Configuration



## 🚧 Next Steps

- Merge this PR into **dev**
- Open Release PR: **main ← dev**
- Tag initial release: **`v0.0.0`**



## 👤 Author
**[ANUJ KUMAR](https://www.linkedin.com/in/anuj-kumar-qa/)** 🏅 QA Consultant & Test Automation Engineer

📝 This feature sets the foundation for the framework. All future features will build on top of this configuration.
