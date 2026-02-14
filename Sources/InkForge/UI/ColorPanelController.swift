import AppKit

class ColorPanelController: NSObject {

    weak var toolManager: ToolManager?

    func showColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isContinuous = true
        panel.showsAlpha = true
        panel.color = toolManager?.currentColor ?? .black
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        toolManager?.currentColor = sender.color
    }
}
