import Foundation

/// Hubs and packages pre-populated in the app. The four HCS hubs are the reference set; the
/// Financial Freedom hub shows how a professional service firm's hub looks with the same structure.
public enum SampleCatalog {

    public static let hubs: [Hub] = [
        Hub(id: "HUB-BA", name: "Business Accelerators", summary: "Improve business performance"),
        Hub(id: "HUB-HT", name: "Human Transformation", summary: "Personal and professional change"),
        Hub(id: "HUB-ST", name: "Society and Technology", summary: "How people and technology shape each other"),
        Hub(id: "HUB-ON", name: "Organizational Navigators", summary: "Leading and navigating organizations"),
        Hub(id: "HUB-FF", name: "Financial Freedom", summary: "Estate, tax and wealth journeys (sample PSF hub)")
    ]

    public static var packages: [HubPackage] { [businessAccelerators, protectedEstate] }

    // MARK: HCS Business Accelerators

    // Sample business cards use reserved example numbers and domains. Replace them with real cards in real packages.
    public static let hcsStudio = Airline(id: "AL-HCS", name: "HCS Studio", type: "behavioral design",
                                          contact: BusinessContact(organization: "Human Complex Systems Studio",
                                                                   phone: "+1 555 0100", email: "studio@example.com",
                                                                   website: "https://example.com/hcs"))

    public static var businessAccelerators: HubPackage {
        let flights = [
            Flight(id: "FL-POD", airlineId: hcsStudio.id, title: "Profit of Dysfunction Diagnostic",
                   description: "Diagnostic built on HCS research", defaultDeliverables: ["Diagnostic report"],
                   typicalDurationDays: 10),
            Flight(id: "FL-AH", airlineId: hcsStudio.id, title: "Anti-Hustle Persuasion Workshop",
                   description: "Course and workshop from the Anti-Hustle material", defaultDeliverables: ["Workshop plan"],
                   typicalDurationDays: 14),
            Flight(id: "FL-BBT", airlineId: hcsStudio.id, title: "Beyond the Black Turtleneck Review",
                   description: "Leadership review from HCS research", defaultDeliverables: ["Review memo"],
                   typicalDurationDays: 10),
            Flight(id: "FL-GOG", airlineId: hcsStudio.id, title: "Gods of Gig Talent Strategy",
                   description: "Talent strategy session from HCS research", defaultDeliverables: ["Strategy brief"],
                   typicalDurationDays: 10)
        ]
        let sprint = JourneyTemplate(
            id: "JT-BAS", title: "Business Acceleration Sprint", destinationTitle: "Accelerator plan adopted",
            successCriteria: ["Diagnostic complete", "Focus chosen", "Workshop delivered"],
            steps: [JourneyStep(flight: "FL-POD"), JourneyStep(customs: "Choose focus area"), JourneyStep(flight: "FL-AH")])
        return HubPackage(
            id: "PKG-BA", hubId: "HUB-BA", publisher: "HCS Studio", title: "HCS Business Accelerators",
            summary: "HCS research, courses and services that make business journeys perform",
            contentRefs: ["Profit of Dysfunction", "Anti-Hustle", "Beyond the Black Turtleneck", "Gods of Gig"],
            journeyTemplates: [sprint], flights: flights, plugins: [],
            airports: [Airport(id: "AP-HCS", name: "HCS Studio", airlineIds: [hcsStudio.id])],
            airlines: [hcsStudio])
    }

    // MARK: Protected Estate (sample PSF package)

    public static let wealthFirm = Airline(id: "AL-WM", name: "Wealth Management Firm", type: "wealth management",
                                           contact: BusinessContact(name: "Dana Advisor", jobTitle: "Wealth advisor",
                                                                    organization: "Wealth Management Firm", phone: "+1 555 0101",
                                                                    email: "dana@wealth.example.com", website: "https://wealth.example.com"))
    public static let lawFirm = Airline(id: "AL-LAW", name: "Estate Law Firm", type: "estate law",
                                        contact: BusinessContact(name: "Sam Counsel", jobTitle: "Estate attorney",
                                                                 organization: "Estate Law Firm", phone: "+1 555 0102",
                                                                 email: "sam@law.example.com", website: "https://law.example.com"))

    public static let decisionNudgeScript = """
    function evaluate(ctx) {
      var out = [];
      var bp = ctx.boardingPass;
      if (!bp) { return out; }
      var limit = parseInt(ctx.settings.waitingDays || "3", 10);
      if (bp.waitingOn === "passenger" && bp.daysWaiting >= limit) {
        out.push({
          severity: "info",
          message: bp.code + " has waited on the Captain for " + bp.daysWaiting + " days",
          recommendation: { message: "HCS note: decisions stall when they feel irreversible. Send the attorney one question at a time." }
        });
      }
      return out;
    }
    """

    public static var decisionNudge: PluginDescriptor {
        PluginDescriptor(id: "hcs.decision-nudge", name: "HCS decision nudge", type: .contentBehavior, tier: .package,
                         signature: Hashing.sha256(decisionNudgeScript), settings: ["waitingDays": "3"],
                         script: decisionNudgeScript)
    }

    public static var protectedEstate: HubPackage {
        let flights = [
            Flight(id: "FL-ER", airlineId: wealthFirm.id, title: "Estate Review & Referral",
                   description: "Review assets and refer to an estate attorney",
                   defaultDeliverables: ["Asset summary and referral"], typicalDurationDays: 7),
            Flight(id: "FL-TR", airlineId: lawFirm.id, title: "Trust Rewrite",
                   description: "Draft the updated trust", defaultDeliverables: ["Final draft of the trust"],
                   typicalDurationDays: 21, pluginIds: ["hcs.decision-nudge"]),
            Flight(id: "FL-PU", airlineId: wealthFirm.id, title: "Portfolio Update",
                   description: "Retitle accounts and align them with the trust",
                   defaultDeliverables: ["Accounts retitled"], typicalDurationDays: 14)
        ]
        let template = JourneyTemplate(
            id: "JT-PE", title: "Protected Estate", destinationTitle: "Trust updated and portfolio aligned",
            successCriteria: ["Trust signed", "Accounts retitled to the trust"],
            steps: [JourneyStep(flight: "FL-ER"), JourneyStep(flight: "FL-TR"),
                    JourneyStep(customs: "Review & Sign", durationDays: 5), JourneyStep(flight: "FL-PU")])
        return HubPackage(
            id: "PKG-PE", hubId: "HUB-FF", publisher: "HCS Studio (sample)", title: "Protected Estate",
            summary: "Estate review, trust rewrite, signing and portfolio update across two firms",
            contentRefs: ["Anti-Hustle"], journeyTemplates: [template], flights: flights, plugins: [decisionNudge],
            airports: [Airport(id: "AP-EST", name: "Trusted Estate Partners", airlineIds: [wealthFirm.id, lawFirm.id])],
            airlines: [wealthFirm, lawFirm])
    }
}
