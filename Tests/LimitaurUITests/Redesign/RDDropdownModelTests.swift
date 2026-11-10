import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: N = exercises new behaviour, I = preserves an invariant. Criterion C3.
// The model is reached through the controller's kept seams (updateDropdown, configureDropdownActions, dropdownModel) so
// the real router wiring is what is observed.

@MainActor private func rdController(demo: Bool, probe: RDRouterProbe) -> AppController {
    _ = NSApplication.shared
    let controller = AppController(demo: demo, countStore: RDCountStore(), actionRouter: probe.router(demo: demo))
    controller.configureDropdownActions()
    controller.settingsPresenter = { _ in }   // no real window in tests
    return controller
}

@Suite @MainActor struct RDDropdownModelTests {
    // N: a normal dropdown offers the header actions, then Quit.
    @Test func normalActionsInVisualOrder() {
        let controller = rdController(demo: false, probe: RDRouterProbe())
        controller.updateDropdown([rdRow("a", label: "Alpha"), rdRow("b", provider: "codex", label: "Beta", health: .throttled)])
        #expect(controller.dropdownModel.actionTitles() == ["Refresh", "Settings", "Quit"])
    }
    // N: each unauthenticated row adds "Connect / Authorize <label>" after the header actions, in row order, before Quit.
    @Test func unauthenticatedRowsAddConnectActions() {
        let controller = rdController(demo: false, probe: RDRouterProbe())
        controller.updateDropdown([rdRow("a", label: "Alpha", health: .unauthenticated), rdRow("b", provider: "codex", label: "Beta"),
                                   rdRow("c", provider: "codex", label: "Gamma", health: .unauthenticated)])
        #expect(controller.dropdownModel.actionTitles() ==
                ["Refresh", "Settings", "Connect / Authorize Alpha", "Connect / Authorize Gamma", "Quit"])
    }
    // I: demo offers no Connect action, even for an unauthenticated row.
    @Test func demoOffersNoConnect() {
        let controller = rdController(demo: true, probe: RDRouterProbe())
        controller.updateDropdown([rdRow("a", label: "Alpha", health: .unauthenticated)])
        #expect(controller.dropdownModel.actionTitles() == ["Refresh", "Settings", "Quit"])
        #expect(controller.dropdownModel.demo)
    }
    // N: with no rows (and not in demo) "Open Settings" sits between the header actions and Quit.
    @Test func emptyDropdownOffersOpenSettings() {
        let controller = rdController(demo: false, probe: RDRouterProbe())
        controller.updateDropdown([])
        #expect(controller.dropdownModel.actionTitles() == ["Refresh", "Settings", "Open Settings", "Quit"])
        #expect(!controller.dropdownModel.demo)
    }
    // N: an empty demo dropdown has no "Open Settings".
    @Test func emptyDemoDropdownHasNoOpenSettings() {
        let controller = rdController(demo: true, probe: RDRouterProbe())
        controller.updateDropdown([])
        #expect(controller.dropdownModel.actionTitles() == ["Refresh", "Settings", "Quit"])
    }
    // N: updateDropdown publishes the rows to the model and the offered actions follow the latest rows.
    @Test func actionsFollowTheLatestRows() {
        let controller = rdController(demo: false, probe: RDRouterProbe())
        controller.updateDropdown([rdRow("a", label: "Alpha", health: .unauthenticated)])
        #expect(controller.dropdownModel.rows.map(\.profile.id) == ["a"])
        #expect(controller.hasDropdownButton("Connect / Authorize Alpha"))
        controller.updateDropdown([rdRow("a", label: "Alpha", health: .healthy)])
        #expect(!controller.hasDropdownButton("Connect / Authorize Alpha") && controller.hasDropdownButton("Settings"))
        controller.updateDropdown([])
        #expect(controller.hasDropdownButton("Open Settings") && !controller.hasDropdownButton("Nope"))
    }
    // N: the model's rows carry what the controller was given, in order.
    @Test func modelPublishesRowsInOrder() {
        let controller = rdController(demo: false, probe: RDRouterProbe())
        let rows = [rdRow("b", provider: "codex"), rdRow("a")]
        controller.updateDropdown(rows)
        #expect(controller.dropdownModel.rows.map(\.profile.id) == ["b", "a"])
    }

    // N: perform routes each title to its closure, through the router.
    @Test func performRoutesToTheRightClosure() {
        let probe = RDRouterProbe()
        let controller = rdController(demo: false, probe: probe)
        controller.updateDropdown([rdRow("claude-default", label: "Alpha", health: .unauthenticated)])
        let model = controller.dropdownModel
        model.perform("Refresh")
        #expect(probe.refreshes == 1 && probe.accounts == 0 && probe.quits == 0 && probe.connected.isEmpty)
        model.perform("Settings")
        #expect(probe.refreshes == 1 && probe.accounts == 1)
        model.perform("Connect / Authorize Alpha")
        #expect(probe.connected == ["claude-default"] && probe.accounts == 1)
        model.perform("Quit")
        #expect(probe.quits == 1 && probe.refreshes == 1 && probe.accounts == 1 && probe.connected == ["claude-default"])
    }
    // N: "Open Settings" on an empty dropdown opens Settings.
    @Test func openSettingsOpensSettings() {
        let probe = RDRouterProbe()
        let controller = rdController(demo: false, probe: probe)
        controller.updateDropdown([])
        controller.dropdownModel.perform("Open Settings")
        #expect(probe.accounts == 1 && probe.refreshes == 0 && probe.quits == 0)
    }
    // N: each Connect action carries its own account id.
    @Test func connectActionsCarryTheirOwnID() {
        let probe = RDRouterProbe()
        let controller = rdController(demo: false, probe: probe)
        controller.updateDropdown([rdRow("claude-default", label: "Alpha", health: .unauthenticated),
                                   rdRow("codex-default", provider: "codex", label: "Beta", health: .unauthenticated)])
        controller.dropdownModel.perform("Connect / Authorize Beta")
        controller.dropdownModel.perform("Connect / Authorize Alpha")
        #expect(probe.connected == ["codex-default", "claude-default"])
    }
    // N: an unknown title does nothing (case matters; empty and near-miss titles included).
    @Test(arguments: ["", "refresh", "Refresh ", "Preferences", "Connect / Authorize Nobody", "Connect / Authorize"])
    func unknownTitleDoesNothing(_ title: String) {
        let probe = RDRouterProbe()
        let controller = rdController(demo: false, probe: probe)
        controller.updateDropdown([rdRow("claude-default", label: "Alpha", health: .unauthenticated)])
        controller.dropdownModel.perform(title)
        #expect(probe.refreshes == 0 && probe.accounts == 0 && probe.quits == 0 && probe.connected.isEmpty)
    }
    // I: in demo Refresh and Connect stay inert and Quit works. F5 (Revision 2): Settings presents through the
    // presenter, not the router; "Open Settings" is not offered in demo.
    @Test func demoPerformOnlyQuits() {
        let probe = RDRouterProbe()
        let controller = rdController(demo: true, probe: probe)
        var presented = 0
        controller.settingsPresenter = { _ in presented += 1 }
        controller.updateDropdown([rdRow("claude-default", label: "Alpha", health: .unauthenticated)])
        for title in ["Refresh", "Open Settings", "Connect / Authorize Alpha"] { controller.dropdownModel.perform(title) }
        #expect(presented == 0 && probe.refreshes == 0 && probe.accounts == 0 && probe.connected.isEmpty && probe.quits == 0)
        controller.dropdownModel.perform("Settings")
        #expect(presented == 1 && probe.accounts == 0)
        controller.dropdownModel.perform("Quit")
        #expect(probe.quits == 1)
    }
    // I: the kept controller seams delegate to the model (press, perform and has).
    @Test func controllerSeamsDelegateToTheModel() {
        let probe = RDRouterProbe()
        let controller = rdController(demo: false, probe: probe)
        controller.updateDropdown([rdRow("claude-default", label: "Alpha", health: .unauthenticated)])
        #expect(controller.hasDropdownButton("Quit") && controller.hasDropdownButton("Connect / Authorize Alpha"))
        controller.pressDropdownButton("Refresh")
        controller.performDropdownButton("Settings")
        controller.routeConnect("claude-default")
        #expect(probe.refreshes == 1 && probe.accounts == 1 && probe.connected == ["claude-default"])
    }
}
