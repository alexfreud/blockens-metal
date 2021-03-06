//
// Created by Bjorn Tipling on 8/8/16.
// Copyright (c) 2016 apphacker. All rights reserved.
//

import Foundation
import MetalKit

struct SpriteLayerInfo {
    var gridWidth: Int32
    var gridHeight: Int32
    var textureWidth: Int32
    var textureHeight: Int32
    var viewDiffRatio : Float32
    var numVertices: Int32
}

class SpriteLayerRenderer: Renderer {

    let renderUtils: RenderUtils

    var timer: NSTimer?
    var interval: NSTimeInterval = 1.0/SPRITE_ANIMATION_FPS;

    private var sprites: [Sprite] = Array()
    private var gridPositions: [Int32] = Array()
    var info: SpriteLayerInfo! = nil
    private var spriteCoordinates: [Float32]? = Array()

    var pipelineState: MTLRenderPipelineState! = nil

    private let textureName: String
    private var texture: MTLTexture! = nil

    private var spriteVertexBuffer: MTLBuffer! = nil
    private var gridPositionsBuffer: MTLBuffer! = nil
    private var spriteInfoBuffer: MTLBuffer! = nil
    private var textCoordBuffer: MTLBuffer! = nil
    private var spriteCoordBuffer: MTLBuffer? = nil

    init (utils: RenderUtils, setup: SpriteLayerSetup) {
        renderUtils = utils
        self.textureName = setup.textureName

        info = SpriteLayerInfo(
                gridWidth: setup.width,
                gridHeight: setup.height,
                textureWidth: setup.textureWidth,
                textureHeight: setup.textureHeight,
                viewDiffRatio: setup.viewDiffRatio,
                numVertices: 0)
    }


    func scheduleTick() {
        if timer?.valid ?? false {
            // If timer isn't nil and is valid don't start a new one.
            return
        }
        timer = NSTimer.scheduledTimerWithTimeInterval(interval, target: self,
                selector: #selector(SpriteLayerRenderer.tick), userInfo: nil, repeats: false)
    }

    @objc func tick() {
        if let currentTimer = timer {
            currentTimer.invalidate()
        }
        update()
        scheduleTick()
    }

    func genGridPosition() throws -> Int32 {
        let range = info.gridWidth * info.gridHeight;
        if Int32(gridPositions.count) >= range {
            throw BlockensError.RuntimeError("No more sprite positions available.")
        }
        var pos: Int32
        repeat {
            pos = getRandomNum(range)
        } while (gridPositions.contains(pos))
        return pos
    }

    func addSprite(sprite: Sprite) {
        sprites.append(sprite)
        sprite.setGridPosition(try! genGridPosition())
        gridPositions.append(sprite.gridPosition())
        info.numVertices += renderUtils.numVerticesInARectangle()
    }

    // Must add all sprites and call update before loading assets.
    func loadAssets(device: MTLDevice, view: MTKView, frameInfo: FrameInfo) {

        pipelineState = renderUtils.createPipeLineState("spriteVertex", fragment: "spriteFragment", device: device, view: view)

        texture = renderUtils.loadTexture(device, name: textureName)

        let maxNumSprites = Int(info.gridWidth * info.gridHeight)

        spriteVertexBuffer = renderUtils.createRectangleVertexBuffer(device, bufferLabel: "sprite layer vertices")
        gridPositionsBuffer = renderUtils.createBufferFromIntArray(device, count: maxNumSprites, bufferLabel: "grid positions")
        spriteCoordBuffer = renderUtils.createBufferFromFloatArray(device, count: spriteCoordinates!.count, bufferLabel: "sprite coordinates")

        textCoordBuffer = renderUtils.createBufferFromFloatArray(device, count: renderUtils.numVerticesInARectangle(), bufferLabel: "text coords tiles")
        renderUtils.updateBufferFromFloatArray(textCoordBuffer, data: renderUtils.rectangleTextureCoords)

        spriteInfoBuffer = device.newBufferWithBytes(&info, length: sizeofValue(info), options: [])

        let contents = spriteInfoBuffer.contents()
        let pointer = UnsafeMutablePointer<SpriteLayerInfo>(contents)
        pointer.initializeFrom(&info!, count: 1)

        print("loading sprite layer assets done")

        updateSprites()
        tick()
    }

    func updateSprites() {
        if gridPositionsBuffer != nil {
            renderUtils.updateBufferFromIntArray(gridPositionsBuffer, data: gridPositions)
        }
    }

    func clear() {
        sprites.removeAll(keepCapacity: true)
        gridPositions.removeAll(keepCapacity: true)
        updateSprites()
        update()
    }

    func update() {

        spriteCoordinates = Array()
        for sprite in sprites {
            spriteCoordinates! += sprite.update()
        }
        if spriteCoordBuffer != nil {
            renderUtils.updateBufferFromFloatArray(spriteCoordBuffer!, data: spriteCoordinates!)
        }
    }

    func render(renderEncoder: MTLRenderCommandEncoder) {

        renderUtils.setPipeLineState(renderEncoder, pipelineState: pipelineState, name: "sprite layer")

    for (i, buffer) in [spriteVertexBuffer, gridPositionsBuffer, spriteCoordBuffer!, textCoordBuffer, spriteInfoBuffer].enumerate() {
            renderEncoder.setVertexBuffer(buffer, offset: 0, atIndex: i)
        }

        renderEncoder.setFragmentTexture(texture, atIndex: 0)

        renderUtils.drawPrimitives(renderEncoder, vertexCount: Int(info.numVertices))
    }

}
