import Foundation
import CoreGraphics
import AppKit

enum SymmetryMode {
    case off
    case vertical    // mirror across vertical axis (left ↔ right)
    case horizontal  // mirror across horizontal axis (top ↔ bottom)
    case quadrant    // both axes (4-way)
}

protocol CanvasModelDelegate: AnyObject {
    func canvasDidChange()
}

class CanvasModel {
    let canvasSize: CGSize
    let layerStack: LayerStack
    weak var delegate: CanvasModelDelegate?

    var symmetryMode: SymmetryMode = .off
    var effectiveSymmetryAxisX: CGFloat { canvasSize.width / 2 }
    var effectiveSymmetryAxisY: CGFloat { canvasSize.height / 2 }

    var selectionMask: SelectionMask?

    var pendingSnapshot: CanvasSnapshot?
    private var customUndoManager: UndoManager?

    var undoManager: UndoManager {
        if customUndoManager == nil {
            customUndoManager = UndoManager()
            customUndoManager?.levelsOfUndo = 20
        }
        return customUndoManager!
    }

    init(size: CGSize) {
        self.canvasSize = size
        self.layerStack = LayerStack(canvasSize: size)
    }

    func snapshotActiveLayerForUndo() {
        guard let layer = layerStack.activeLayer,
              let image = layer.makeImage() else { return }

        pendingSnapshot = CanvasSnapshot(
            layerIndex: layerStack.activeLayerIndex,
            image: image,
            maskImage: layer.makeMaskImage(),
            textContent: layer.textContent
        )
    }

    func clearPendingSnapshot() {
        pendingSnapshot = nil
    }

    func registerUndoForActiveLayer(actionName: String) {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil

        let mgr = undoManager
        mgr.registerUndo(withTarget: self) { target in
            guard let currentLayer = target.layerStack.layers[safe: snapshot.layerIndex],
                  let currentImage = currentLayer.makeImage() else { return }

            let currentMaskImage = currentLayer.makeMaskImage()
            let currentTextContent = currentLayer.textContent

            currentLayer.restoreFromImage(snapshot.image)
            if let maskImg = snapshot.maskImage {
                currentLayer.restoreMaskFromImage(maskImg)
            }
            currentLayer.restoreTextContent(snapshot.textContent)

            let redoSnapshot = CanvasSnapshot(layerIndex: snapshot.layerIndex,
                                              image: currentImage,
                                              maskImage: currentMaskImage,
                                              textContent: currentTextContent)
            mgr.registerUndo(withTarget: target) { target2 in
                guard let layer2 = target2.layerStack.layers[safe: redoSnapshot.layerIndex] else { return }
                layer2.restoreFromImage(redoSnapshot.image)
                if let maskImg = redoSnapshot.maskImage {
                    layer2.restoreMaskFromImage(maskImg)
                }
                layer2.restoreTextContent(redoSnapshot.textContent)
                target2.delegate?.canvasDidChange()
            }

            target.delegate?.canvasDidChange()
        }
        mgr.setActionName(actionName)
    }

    func registerUndoForLayerAddition(at index: Int, actionName: String) {
        let layer = layerStack.layers[index]
        let mgr = undoManager
        mgr.registerUndo(withTarget: self) { target in
            target.layerStack.removeLayerForUndo(at: index)

            mgr.registerUndo(withTarget: target) { target2 in
                target2.layerStack.insertLayerForUndo(layer, at: index)
                target2.delegate?.canvasDidChange()
            }

            target.delegate?.canvasDidChange()
        }
        mgr.setActionName(actionName)
    }

    func undo() {
        undoManager.undo()
    }

    func redo() {
        undoManager.redo()
    }

    // MARK: - Selection

    @discardableResult
    func ensureSelectionMask() -> SelectionMask {
        if let mask = selectionMask { return mask }
        let mask = SelectionMask(width: Int(canvasSize.width), height: Int(canvasSize.height))
        selectionMask = mask
        return mask
    }

    func deselect() {
        selectionMask?.clear()
        selectionMask = nil
    }

    func invertSelection() {
        let mask = ensureSelectionMask()
        if mask.isEmpty {
            mask.selectAll()
        } else {
            mask.invert()
        }
    }

    func selectAll() {
        ensureSelectionMask().selectAll()
    }
}
