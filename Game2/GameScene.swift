import SpriteKit
import AppKit

struct PhysicsCategory {
    static let ball: UInt32 = 0x1 << 0
    static let paddle: UInt32 = 0x1 << 1
    static let wall: UInt32 = 0x1 << 2
    static let brick: UInt32 = 0x1 << 3
}

class GameScene: SKScene, SKPhysicsContactDelegate {
    
    let ball = SKShapeNode(circleOfRadius: 20)
    let paddle = SKSpriteNode(color: .white, size: CGSize(width: 120, height: 20))
    
    var score = 25
    var highScore = UserDefaults.standard.integer(forKey: "HighScore")
    var soundOn = UserDefaults.standard.bool(forKey: "SoundOn")
    var level = 1
    var hiddenRowsRemaining = 0
    let maxVisibleRows = 7
    let bricksPerRow = 8
    
    var isPlaying = false
    var gamePaused = false
    var isGameOver = false
    var ballArmed = false
    var startTime: TimeInterval = 0
    var pausedVelocity: CGVector = .zero
    
    let baseSpeed: CGFloat = 400
    let speedStep: CGFloat = 0.08
    
    var scoreLabel: SKLabelNode!
    var timeLabel: SKLabelNode!
    var highScoreLabel: SKLabelNode!
    var speedLabel: SKLabelNode!
    var levelLabel: SKLabelNode!
    var gameOverLabel: SKLabelNode!
    var statusButton: SKShapeNode!
    var statusButtonLabel: SKLabelNode!
    var speakerButton: SKShapeNode!
    var speakerLabel: SKLabelNode!
    var resetButton: SKShapeNode!
    var resetButtonLabel: SKLabelNode!
    
    var levelBox: SKShapeNode!
    var highBox: SKShapeNode!
    var speedBox: SKShapeNode!
    var timeBox: SKShapeNode!
    var scoreBox: SKShapeNode!

    override func didMove(to view: SKView) {
        if UserDefaults.standard.object(forKey: "SoundOn") == nil { soundOn = true }
        let savedLevel = UserDefaults.standard.integer(forKey: "CurrentLevel")
        level = savedLevel == 0 ? 1 : savedLevel
        
        backgroundColor = .black
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = .zero
        view.window?.acceptsMouseMovedEvents = true
        
        createWalls()
        
        ball.fillColor = .systemYellow
        ball.strokeColor = .clear
        ball.physicsBody = SKPhysicsBody(circleOfRadius: 20)
        ball.physicsBody?.categoryBitMask = PhysicsCategory.ball
        ball.physicsBody?.restitution = 1
        ball.physicsBody?.friction = 0
        ball.physicsBody?.linearDamping = 0
        addChild(ball)

        paddle.physicsBody = SKPhysicsBody(rectangleOf: paddle.size)
        paddle.physicsBody?.categoryBitMask = PhysicsCategory.paddle
        paddle.physicsBody?.contactTestBitMask = PhysicsCategory.ball
        paddle.physicsBody?.collisionBitMask = PhysicsCategory.ball
        paddle.physicsBody?.isDynamic = false
        paddle.position = CGPoint(x: size.width/2, y: 80)
        addChild(paddle)
        
        setupHUD()
        layoutHUD()
        prepareGame()
    }
    
    func createWalls() {
        for n in children where n.name == "leftWall" || n.name == "rightWall" || n.name == "topWall" {
            n.removeFromParent()
        }
        let left = SKNode(); left.name = "leftWall"
        left.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: size.height))
        left.physicsBody?.categoryBitMask = PhysicsCategory.wall; addChild(left)
        let right = SKNode(); right.name = "rightWall"
        right.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: size.width, y: 0), to: CGPoint(x: size.width, y: size.height))
        right.physicsBody?.categoryBitMask = PhysicsCategory.wall; addChild(right)
        let top = SKNode(); top.name = "topWall"
        top.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: size.height), to: CGPoint(x: size.width, y: size.height))
        top.physicsBody?.categoryBitMask = PhysicsCategory.wall; addChild(top)
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if statusButton == nil { return }
        createWalls()
        layoutHUD()
        paddle.position.y = 80
        if !isPlaying {
            ball.position = CGPoint(x: size.width/2, y: size.height/2)
        }
    }
    
    func setupHUD() {
        statusButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 75, height: 32), cornerRadius: 8)
        statusButton.fillColor = .systemGreen; statusButton.strokeColor = .white
        statusButton.name = "statusButton"; addChild(statusButton)
        statusButtonLabel = SKLabelNode(fontNamed: "Menlo-Bold"); statusButtonLabel.fontSize = 11
        statusButtonLabel.fontColor = .black; statusButtonLabel.position = CGPoint(x: 37, y: 8)
        statusButton.addChild(statusButtonLabel)
        
        speakerButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 50, height: 32), cornerRadius: 8)
        speakerButton.fillColor = SKColor(white: 0.25, alpha: 0.9); speakerButton.strokeColor = .white
        speakerButton.name = "speakerButton"; addChild(speakerButton)
        speakerLabel = SKLabelNode(fontNamed: "Menlo-Bold"); speakerLabel.fontSize = 10
        speakerLabel.position = CGPoint(x: 25, y: 8); speakerButton.addChild(speakerLabel)
        
        levelBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 85, height: 32), cornerRadius: 8)
        levelBox.fillColor = SKColor(white: 0.2, alpha: 0.9); levelBox.strokeColor = .systemPurple
        levelBox.name = "levelBox"
        addChild(levelBox)
        levelLabel = SKLabelNode(fontNamed: "Menlo-Bold"); levelLabel.fontSize = 11; levelLabel.fontColor = .systemPurple
        levelLabel.position = CGPoint(x: 42, y: 8); levelBox.addChild(levelLabel)
        
        highBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        highBox.fillColor = SKColor(white: 0.2, alpha: 0.9); highBox.strokeColor = .white
        addChild(highBox)
        highScoreLabel = SKLabelNode(fontNamed: "Menlo-Bold"); highScoreLabel.fontSize = 10; highScoreLabel.fontColor = .cyan
        highScoreLabel.position = CGPoint(x: 47, y: 8); highBox.addChild(highScoreLabel)
        
        speedBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        speedBox.fillColor = SKColor(white: 0.2, alpha: 0.9); speedBox.strokeColor = .yellow
        addChild(speedBox)
        speedLabel = SKLabelNode(fontNamed: "Menlo-Bold"); speedLabel.fontSize = 10; speedLabel.fontColor = .yellow
        speedLabel.position = CGPoint(x: 47, y: 8); speedBox.addChild(speedLabel)
        
        resetButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        resetButton.fillColor = SKColor(white: 0.25, alpha: 0.9); resetButton.strokeColor = .systemRed
        resetButton.name = "resetButton"
        addChild(resetButton)
        resetButtonLabel = SKLabelNode(fontNamed: "Menlo-Bold"); resetButtonLabel.fontSize = 10; resetButtonLabel.fontColor = .systemRed
        resetButtonLabel.text = "RESET ALL"
        resetButtonLabel.position = CGPoint(x: 47, y: 8); resetButton.addChild(resetButtonLabel)
        
        timeBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 90, height: 32), cornerRadius: 8)
        timeBox.fillColor = SKColor(white: 0.2, alpha: 0.9); timeBox.strokeColor = .white
        addChild(timeBox)
        timeLabel = SKLabelNode(fontNamed: "Menlo-Bold"); timeLabel.fontSize = 10
        timeLabel.position = CGPoint(x: 45, y: 8); timeBox.addChild(timeLabel)
        
        scoreBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 90, height: 32), cornerRadius: 8)
        scoreBox.fillColor = SKColor(white: 0.2, alpha: 0.9); scoreBox.strokeColor = .white
        addChild(scoreBox)
        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold"); scoreLabel.fontSize = 10; scoreLabel.fontColor = .systemYellow
        scoreLabel.position = CGPoint(x: 45, y: 8); scoreBox.addChild(scoreLabel)
        
        gameOverLabel = SKLabelNode(fontNamed: "Menlo-Bold"); gameOverLabel.fontSize = 24
        addChild(gameOverLabel)
    }
    
    func layoutHUD() {
        guard statusButton != nil else { return }
        statusButton.position = CGPoint(x: 15, y: size.height - 50)
        speakerButton.position = CGPoint(x: 100, y: size.height - 50)
        levelBox.position = CGPoint(x: 160, y: size.height - 50)
        highBox.position = CGPoint(x: 255, y: size.height - 50)
        speedBox.position = CGPoint(x: 360, y: size.height - 50)
        resetButton.position = CGPoint(x: size.width - 295, y: size.height - 50)
        timeBox.position = CGPoint(x: size.width - 190, y: size.height - 50)
        scoreBox.position = CGPoint(x: size.width - 90, y: size.height - 50)
        gameOverLabel?.position = CGPoint(x: size.width/2, y: size.height/2 + 60)
    }
    
    func createBricks(rows: Int) {
        for n in children where n.name == "brick" { n.removeFromParent() }
        let brickW: CGFloat = 75, brickH: CGFloat = 22, pad: CGFloat = 6
        let totalW = CGFloat(bricksPerRow)*brickW + CGFloat(bricksPerRow-1)*pad
        let startX = (size.width - totalW)/2
        let startY = size.height - 110
        let colors: [SKColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .cyan, .systemPurple, .systemPink]
        for r in 0..<rows {
            for c in 0..<bricksPerRow {
                let brick = SKSpriteNode(color: colors[(r + level) % colors.count], size: CGSize(width: brickW, height: brickH))
                brick.position = CGPoint(x: startX + CGFloat(c)*(brickW+pad) + brickW/2, y: startY - CGFloat(r)*(brickH+pad))
                brick.name = "brick"
                brick.physicsBody = SKPhysicsBody(rectangleOf: brick.size)
                brick.physicsBody?.isDynamic = false
                brick.physicsBody?.categoryBitMask = PhysicsCategory.brick
                addChild(brick)
            }
        }
    }
    
    func setupLevel(_ lvl: Int) {
        level = lvl
        UserDefaults.standard.set(level, forKey: "CurrentLevel")
        let visible = min(lvl, maxVisibleRows)
        hiddenRowsRemaining = lvl - visible
        createBricks(rows: visible)
        updateHUD()
    }
    
    func disarmBall() {
        ballArmed = false
        ball.physicsBody?.collisionBitMask = PhysicsCategory.paddle | PhysicsCategory.wall
        ball.physicsBody?.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.wall
        ball.fillColor = .systemGray
    }
    func armBall() {
        ballArmed = true
        ball.physicsBody?.collisionBitMask = PhysicsCategory.paddle | PhysicsCategory.wall | PhysicsCategory.brick
        ball.physicsBody?.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.brick | PhysicsCategory.wall
        ball.fillColor = .systemYellow
    }
    func currentSpeed() -> CGFloat {
        let diff = CGFloat(score - 25) / 10.0
        return baseSpeed * max(0.5, min(1.0 + diff*speedStep, 2.5)) * (1.0 + CGFloat(level)*0.05)
    }
    func playHitSound() { if soundOn { NSSound(named: "Pop")?.play() } }
    func playMissSound() { if soundOn { NSSound(named: "Basso")?.play() } }
    func updateHUD() {
        scoreLabel.text = String(format: "Points: %02d", score)
        highScoreLabel.text = String(format: "High: %02d", highScore)
        speedLabel.text = "Speed: \(Int(currentSpeed()/baseSpeed*100))%"
        speakerLabel.text = soundOn ? "ON" : "OFF"
        if hiddenRowsRemaining > 0 { levelLabel.text = "Level: \(level) (+\(hiddenRowsRemaining))" }
        else { levelLabel.text = "Level: \(level)" }
        if isGameOver { statusButtonLabel.text = "START"; statusButton.fillColor = .systemGreen }
        else if isPlaying { statusButtonLabel.text = "PLAYING"; statusButton.fillColor = .systemGreen }
        else if gamePaused { statusButtonLabel.text = "PAUSED"; statusButton.fillColor = .systemYellow }
        else { statusButtonLabel.text = "START"; statusButton.fillColor = .systemGreen }
    }
    func prepareGame() {
        isPlaying = false; gamePaused = false; isGameOver = false
        setupLevel(level); disarmBall()
        ball.position = CGPoint(x: size.width/2, y: size.height/2)
        ball.physicsBody?.velocity = .zero
        ball.isHidden = false
        gameOverLabel.text = "Press SpaceBar to Play"; gameOverLabel.fontColor = .white; gameOverLabel.isHidden = false
        updateHUD()
    }
    func launchBall() {
        disarmBall()
        let speed = currentSpeed()
        let angle = CGFloat.random(in: 35...145) * .pi / 180
        ball.physicsBody?.velocity = CGVector(dx: cos(angle)*speed, dy: sin(angle)*speed)
    }
    func handleStatusToggle() {
        if isGameOver { restartGame(); return }
        if isPlaying {
            gamePaused = true; isPlaying = false
            pausedVelocity = ball.physicsBody?.velocity ?? .zero
            ball.physicsBody?.velocity = .zero
            gameOverLabel.text = "PAUSED"; gameOverLabel.fontColor = .yellow; gameOverLabel.isHidden = false
        } else {
            if gamePaused {
                gamePaused = false; isPlaying = true
                ball.physicsBody?.velocity = pausedVelocity
                gameOverLabel.isHidden = true
            } else {
                isPlaying = true; gameOverLabel.isHidden = true; launchBall()
            }
        }
        updateHUD()
    }
    func toggleSound() { soundOn.toggle(); UserDefaults.standard.set(soundOn, forKey: "SoundOn"); updateHUD(); if soundOn { playHitSound() } }
    func restartGame() { score = 25; prepareGame() }
    
    func promptForLevel() {
        if isPlaying {
            gamePaused = true; isPlaying = false
            pausedVelocity = ball.physicsBody?.velocity ?? .zero
            ball.physicsBody?.velocity = .zero
        }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Change Level"
            alert.informativeText = "Enter level number (1-99):"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
            textField.stringValue = "\(self.level)"
            alert.accessoryView = textField
            alert.window.initialFirstResponder = textField
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let newLevel = Int(textField.stringValue), (1...99).contains(newLevel) {
                    self.level = newLevel
                    UserDefaults.standard.set(newLevel, forKey: "CurrentLevel")
                    self.score = 25
                    self.prepareGame()
                }
            } else {
                if self.gamePaused {
                    self.gamePaused = false; self.isPlaying = true
                    self.ball.physicsBody?.velocity = self.pausedVelocity
                    self.gameOverLabel.isHidden = true
                    self.updateHUD()
                }
            }
        }
    }
    
    func confirmResetAll() {
        if isPlaying {
            gamePaused = true; isPlaying = false
            pausedVelocity = ball.physicsBody?.velocity ?? .zero
            ball.physicsBody?.velocity = .zero
        }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Reset All Progress?"
            alert.informativeText = "This will reset score, high score and level to 1. This cannot be undone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Reset All")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.resetAllProgress()
            } else {
                if self.gamePaused {
                    self.gamePaused = false; self.isPlaying = true
                    self.ball.physicsBody?.velocity = self.pausedVelocity
                    self.gameOverLabel.isHidden = true
                    self.updateHUD()
                }
            }
        }
    }
    
    func resetAllProgress() {
        score = 25
        highScore = 0
        level = 1
        UserDefaults.standard.removeObject(forKey: "HighScore")
        UserDefaults.standard.removeObject(forKey: "CurrentLevel")
        UserDefaults.standard.set(0, forKey: "HighScore")
        UserDefaults.standard.set(1, forKey: "CurrentLevel")
        prepareGame()
    }
    
    func makeBrickFall(_ brick: SKNode) {
        guard let brickSprite = brick as? SKSpriteNode else {
            brick.removeFromParent()
            return
        }
        brick.name = nil
        let originalColor = brickSprite.color
        let originalSize = brickSprite.size
        
        // Container for 3D tumbling
        let container = SKNode()
        container.position = brick.position
        container.zPosition = 10
        addChild(container)
        brick.removeFromParent()
        
        // Shadow on ground
        let shadow = SKShapeNode(ellipseOf: CGSize(width: originalSize.width*0.9, height: 12))
        shadow.fillColor = .black
        shadow.strokeColor = .clear
        shadow.alpha = 0.35
        shadow.position = CGPoint(x: 0, y: -size.height/2 + 80)
        shadow.zPosition = -1
        container.addChild(shadow)
        
        // Main brick face
        let front = SKSpriteNode(color: originalColor, size: originalSize)
        front.zPosition = 1
        container.addChild(front)
        
        // Top edge for thickness illusion
        let topEdge = SKSpriteNode(color: originalColor.blended(withFraction: 0.35, of: .white) ?? originalColor, size: CGSize(width: originalSize.width, height: 6))
        topEdge.position = CGPoint(x: 0, y: originalSize.height/2)
        topEdge.zPosition = 0
        container.addChild(topEdge)
        
        // Side edge
        let sideEdge = SKSpriteNode(color: originalColor.blended(withFraction: 0.35, of: .black) ?? originalColor, size: CGSize(width: 6, height: originalSize.height))
        sideEdge.position = CGPoint(x: originalSize.width/2, y: 0)
        sideEdge.zPosition = 0
        container.addChild(sideEdge)
        
        // Physics for natural fall - FIXED: use CGFloat ranges
        container.physicsBody = SKPhysicsBody(rectangleOf: originalSize)
        container.physicsBody?.isDynamic = true
        container.physicsBody?.collisionBitMask = 0
        container.physicsBody?.categoryBitMask = 0
        container.physicsBody?.contactTestBitMask = 0
        container.physicsBody?.velocity = CGVector(dx: CGFloat.random(in: -120.0...120.0), dy: CGFloat.random(in: -380.0...(-280.0)))
        container.physicsBody?.angularVelocity = CGFloat.random(in: -8.0...8.0)
        container.physicsBody?.linearDamping = 0.2
        
        // 3D tumble: flip around Y (xScale) and X (yScale) while falling
        let duration: CGFloat = 2.4
        let tumble3D = SKAction.customAction(withDuration: TimeInterval(duration)) { node, elapsed in
            let t = elapsed / CGFloat(duration)
            let spinY = t * .pi * 6.0
            let xScale = cos(spinY)
            let spinX = t * .pi * 3.0
            let yScale = 0.55 + 0.45 * abs(cos(spinX))
            
            front.xScale = xScale
            front.yScale = yScale
            topEdge.xScale = xScale
            
            let isBackface = xScale < 0
            if isBackface {
                front.color = originalColor.blended(withFraction: 0.35, of: .black) ?? originalColor
                topEdge.isHidden = true
                sideEdge.isHidden = false
            } else {
                front.color = originalColor
                topEdge.isHidden = false
                sideEdge.isHidden = xScale < 0.4
            }
            let edgeOn = abs(xScale) < 0.25
            topEdge.alpha = edgeOn ? 1.0 : 0.85
            sideEdge.alpha = edgeOn ? 1.0 : 0.7
            shadow.xScale = 1.0 - t*0.5
            shadow.alpha = 0.35 * (1.0 - t)
        }
        
        let fadeAndShrink = SKAction.group([
            SKAction.sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 1.0)]),
            SKAction.sequence([.wait(forDuration: 0.6), .scale(to: 0.35, duration: 1.8)])
        ])
        
        container.run(.sequence([
            .group([tumble3D, fadeAndShrink]),
            .removeFromParent()
        ]))
    }
    func handleMiss() {
        playMissSound(); score -= 5
        if score <= 0 {
            score = 0; isPlaying = false; isGameOver = true
            ball.physicsBody?.velocity = .zero; ball.isHidden = true
            gameOverLabel.text = "GAME OVER"; gameOverLabel.fontColor = .red; gameOverLabel.isHidden = false
        } else {
            if score > highScore { highScore = score; UserDefaults.standard.set(highScore, forKey: "HighScore") }
            ball.position = CGPoint(x: size.width/2, y: size.height/2); launchBall()
        }
        updateHUD()
    }
    func handleWallHit(wallName: String) {
        let speed = currentSpeed()
        var angle = atan2(ball.physicsBody!.velocity.dy, ball.physicsBody!.velocity.dx)
        if wallName == "leftWall" || wallName == "rightWall" { angle += CGFloat.random(in: -0.45...0.45) }
        else { angle += CGFloat.random(in: -0.35...0.35) }
        if abs(sin(angle)) < 0.35 { angle += sin(angle) >= 0 ? 0.35 : -0.35 }
        ball.physicsBody?.velocity = CGVector(dx: cos(angle)*speed, dy: sin(angle)*speed)
        playHitSound()
    }
    func didBegin(_ contact: SKPhysicsContact) {
        if !isPlaying { return }
        let a = contact.bodyA, b = contact.bodyB
        if a.categoryBitMask == PhysicsCategory.wall || b.categoryBitMask == PhysicsCategory.wall {
            let wallNode = a.categoryBitMask == PhysicsCategory.wall ? a.node : b.node
            handleWallHit(wallName: wallNode?.name ?? "wall"); return
        }
        if (a.categoryBitMask == PhysicsCategory.ball && b.categoryBitMask == PhysicsCategory.paddle) ||
           (a.categoryBitMask == PhysicsCategory.paddle && b.categoryBitMask == PhysicsCategory.ball) {
            score += 1
            if score > highScore { highScore = score; UserDefaults.standard.set(highScore, forKey: "HighScore") }
            playHitSound(); armBall()
            let speed = currentSpeed()
            let angle = CGFloat.random(in: 25...155) * .pi / 180
            var dx = cos(angle)*speed
            let hitPos = (ball.position.x - paddle.position.x) / (paddle.size.width/2)
            dx += hitPos * 120
            ball.physicsBody?.velocity = CGVector(dx: dx, dy: abs(sin(angle)*speed))
            updateHUD(); return
        }
        if a.categoryBitMask == PhysicsCategory.brick || b.categoryBitMask == PhysicsCategory.brick {
            if !ballArmed { return }
            let brick = a.categoryBitMask == PhysicsCategory.brick ? a.node : b.node
            if let brick = brick {
                makeBrickFall(brick); score += 2
                if score > highScore { highScore = score; UserDefaults.standard.set(highScore, forKey: "HighScore") }
                playHitSound(); disarmBall(); updateHUD()
                let remaining = children.filter({ $0.name == "brick" }).count
                if remaining == 0 {
                    if hiddenRowsRemaining > 0 {
                        let nextBatch = min(hiddenRowsRemaining, maxVisibleRows)
                        hiddenRowsRemaining -= nextBatch
                        gameOverLabel.text = "NEXT WAVE!"; gameOverLabel.fontColor = .orange; gameOverLabel.isHidden = false
                        DispatchQueue.main.asyncAfter(deadline: .now()+0.8) {
                            self.createBricks(rows: nextBatch)
                            self.ball.position = CGPoint(x: self.size.width/2, y: self.size.height/2)
                            self.launchBall(); self.isPlaying = true; self.gameOverLabel.isHidden = true
                            self.updateHUD()
                        }
                    } else {
                        isPlaying = false
                        gameOverLabel.text = "LEVEL \(level) CLEAR!"; gameOverLabel.fontColor = .green; gameOverLabel.isHidden = false
                        DispatchQueue.main.asyncAfter(deadline: .now()+1.5) {
                            self.setupLevel(self.level + 1)
                            self.ball.position = CGPoint(x: self.size.width/2, y: self.size.height/2)
                            self.launchBall(); self.isPlaying = true; self.gameOverLabel.isHidden = true
                        }
                    }
                }
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        let loc = event.location(in: self)
        let nodes = nodes(at: loc)
        for n in nodes {
            if n.name == "statusButton" || n.parent?.name == "statusButton" { handleStatusToggle(); return }
            if n.name == "speakerButton" || n.parent?.name == "speakerButton" { toggleSound(); return }
            if n.name == "resetButton" || n.parent?.name == "resetButton" { confirmResetAll(); return }
            if n.name == "levelBox" || n === levelLabel || n.parent === levelBox { promptForLevel(); return }
        }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 49 { handleStatusToggle() } }
    override func update(_ currentTime: TimeInterval) {
        if !isPlaying { return }
        if let view = self.view, let window = view.window {
            let mW = window.mouseLocationOutsideOfEventStream
            let mV = view.convert(mW, from: nil)
            paddle.position.x = convertPoint(fromView: mV).x
        }
        if ball.position.y < 20 { handleMiss() }
        if startTime == 0 { startTime = currentTime }
        let elapsed = currentTime - startTime
        timeLabel.text = String(format: "%02d:%05.2f", Int(elapsed)/60, elapsed.truncatingRemainder(dividingBy: 60))
    }
}
