//
//  GameViewController.swift
//  blockens
//
//  Created by Bjorn Tipling on 7/22/16.
//  Copyright (c) 2016 apphacker. All rights reserved.
//

import Cocoa
import MetalKit

let MaxBuffers = 3

let ConstantBufferSize = 1024*1024

let vertexData:[Float] =
[
    -1.0, -1.0,
    -1.0,  1.0,
    1.0, -1.0,

    1.0, -1.0,
    -1.0,  1.0,
    1.0,  1.0,
]


// generate a large enough buffer to allow streaming vertices for 3 semaphore controlled frames
//let vertexBufferSize = (vertexData.count * sizeofValue(vertexData[0]) * MaxBuffers);

let vertexColorData:[Float] =
[
    0.0, 0.0, 1.0, 1.0,
    1.0, 1.0, 0.0, 1.0,
]


struct GridInfo {
    var gridDimension: Int32
    var gridOffset: Float32
    var numBoxes: Int32
    var numVertices: Int32
    var numColors: Int32
}

var gridDimension: Int32 = 25;
var gridInfoData = GridInfo(
        gridDimension: gridDimension,
        gridOffset: 2.0/Float32(gridDimension),
        numBoxes: Int32(pow(Float(gridDimension), 2.0)),
        numVertices: Int32(vertexData.count/2),
        numColors: Int32(vertexColorData.count/4))

let vertexCount = Int(gridInfoData.numVertices * gridInfoData.numBoxes)

class GameViewController: NSViewController, MTKViewDelegate {
    
    var device: MTLDevice! = nil
    
    var commandQueue: MTLCommandQueue! = nil
    var pipelineState: MTLRenderPipelineState! = nil
    var vertexBuffer: MTLBuffer! = nil
    var vertexColorBuffer: MTLBuffer! = nil
    var gridInfoBuffer: MTLBuffer! = nil
    
    let inflightSemaphore = dispatch_semaphore_create(MaxBuffers)
    var bufferIndex = 0

    override func viewDidLoad() {
        
        super.viewDidLoad()
        let appDelegate = NSApplication.sharedApplication().delegate as! AppDelegate
        let gameWindow = appDelegate.getWindow()
        gameWindow.addKeyEventCallback(handleKeyEvent)
        
        device = MTLCreateSystemDefaultDevice()
        guard device != nil else { // Fallback to a blank NSView, an application could also fallback to OpenGL here.
            print("Metal is not supported on this device")
            self.view = NSView(frame: self.view.frame)
            return
        }

        // setup view properties
        let view = self.view as! MTKView
        view.delegate = self
        view.device = device
        view.sampleCount = 4
        
        loadAssets()
    }

    func handleKeyEvent(event: NSEvent) {

        Swift.print("Got a key down in game view controller \(event.keyCode) yay!!")
    }
    
    func loadAssets() {
        
        // load any resources required for rendering
        let view = self.view as! MTKView
        commandQueue = device.newCommandQueue()
        commandQueue.label = "main command queue"
        
        let defaultLibrary = device.newDefaultLibrary()!
        let fragmentProgram = defaultLibrary.newFunctionWithName("passThroughFragment")!
        let vertexProgram = defaultLibrary.newFunctionWithName("passThroughVertex")!
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineStateDescriptor.sampleCount = view.sampleCount
        
        do {
            try pipelineState = device.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor)
        } catch let error {
            print("Failed to create pipeline state, error \(error)")
        }


        vertexBuffer = device.newBufferWithLength(ConstantBufferSize, options: [])
        vertexBuffer.label = "vertices"
        
        let vertexColorSize = vertexColorData.count * sizeofValue(vertexColorData[0])
        vertexColorBuffer = device.newBufferWithBytes(vertexColorData, length: vertexColorSize, options: [])
        vertexColorBuffer.label = "colors"

        let gridInfoBufferSize = sizeofValue(gridInfoData)
        gridInfoBuffer = device.newBufferWithBytes(&gridInfoData, length: gridInfoBufferSize, options: [])
        gridInfoBuffer.label = "gridInfo"
    }
    
    func update() {
        
        // vData is pointer to the MTLBuffer's Float data contents
        let pData = vertexBuffer.contents()
        let vData = UnsafeMutablePointer<Float>(pData + 256*bufferIndex)

        // reset the vertices to default before adding animated offsets
        vData.initializeFrom(vertexData)

    }
    
    func drawInMTKView(view: MTKView) {
        
        // use semaphore to encode 3 frames ahead
        dispatch_semaphore_wait(inflightSemaphore, DISPATCH_TIME_FOREVER)
        
        self.update()
        
        let commandBuffer = commandQueue.commandBuffer()
        commandBuffer.label = "Frame command buffer"
        
        // use completion handler to signal the semaphore when this frame is completed allowing the encoding of the next frame to proceed
        // use capture list to avoid any retain cycles if the command buffer gets retained anywhere besides this stack frame
        commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
            if let strongSelf = self {
                dispatch_semaphore_signal(strongSelf.inflightSemaphore)
            }
            return
        }
        
        if let renderPassDescriptor = view.currentRenderPassDescriptor, currentDrawable = view.currentDrawable
        {
            let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor)
            renderEncoder.label = "render encoder"
            
            renderEncoder.pushDebugGroup("draw morphing triangle")
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 256*bufferIndex, atIndex: 0)
            renderEncoder.setVertexBuffer(vertexColorBuffer, offset:0 , atIndex: 1)
            renderEncoder.setVertexBuffer(gridInfoBuffer, offset:0 , atIndex: 2)
            renderEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: vertexCount, instanceCount: 1)
            
            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
                
            commandBuffer.presentDrawable(currentDrawable)
        }
        
        // bufferIndex matches the current semaphore controled frame index to ensure writing occurs at the correct region in the vertex buffer
        bufferIndex = (bufferIndex + 1) % MaxBuffers
        
        commandBuffer.commit()
    }
    
    
    func mtkView(view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}
