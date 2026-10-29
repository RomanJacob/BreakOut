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
        if statusButton == nil { return } // Kaldes før didMove
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
        
        let levelBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 85, height: 32), cornerRadius: 8)
        levelBox.fillColor = SKColor(white: 0.2, alpha: 0.9); levelBox.strokeColor = .systemPurple
        addChild(levelBox)
        levelLabel = SKLabelNode(fontNamed: "Menlo-Bold"); levelLabel.fontSize = 11; levelLabel.fontColor = .systemPurple
        levelLabel.position = CGPoint(x: 42, y: 8); levelBox.addChild(levelLabel)
        
        let highBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        highBox.fillColor = SKColor(white: 0.2, alpha: 0.9); highBox.strokeColor = .white
        addChild(highBox)
        highScoreLabel = SKLabelNode(fontNamed: "Menlo-Bold"); highScoreLabel.fontSize = 10; highScoreLabel.fontColor = .cyan
        highScoreLabel.position = CGPoint(x: 47, y: 8); highBox.addChild(highScoreLabel)
        
        let speedBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        speedBox.fillColor = SKColor(white: 0.2, alpha: 0.9); speedBox.strokeColor = .yellow
        addChild(speedBox)
        speedLabel = SKLabelNode(fontNamed: "Menlo-Bold"); speedLabel.fontSize = 10; speedLabel.fontColor = .yellow
        speedLabel.position = CGPoint(x: 47, y: 8); speedBox.addChild(speedLabel)
        
        let timeBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 90, height: 32), cornerRadius: 8)
        timeBox.fillColor = SKColor(white: 0.2, alpha: 0.9); timeBox.strokeColor = .white
        addChild(timeBox)
        timeLabel = SKLabelNode(fontNamed: "Menlo-Bold"); timeLabel.fontSize = 10
        timeLabel.position = CGPoint(x: 45, y: 8); timeBox.addChild(timeLabel)
        
        let scoreBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 90, height: 32), cornerRadius: 8)
        scoreBox.fillColor = SKColor(white: 0.2, alpha: 0.9); scoreBox.strokeColor = .white
        addChild(scoreBox)
        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold"); scoreLabel.fontSize = 10; scoreLabel.fontColor = .systemYellow
        scoreLabel.position = CGPoint(x: 45, y: 8); scoreBox.addChild(scoreLabel)
        
        gameOverLabel = SKLabelNode(fontNamed: "Menlo-Bold"); gameOverLabel.fontSize = 24
        addChild(gameOverLabel)
    }
    
    func layoutHUD() {
        guard statusButton != nil, levelLabel != nil else { return }
        statusButton.position = CGPoint(x: 15, y: size.height - 50)
        speakerButton.position = CGPoint(x: 100, y: size.height - 50)
        for child in children {
            if child.children.contains(where: { $0 === levelLabel }) { child.position = CGPoint(x: 160, y: size.height - 50) }
            if child.children.contains(where: { $0 === highScoreLabel }) { child.position = CGPoint(x: 255, y: size.height - 50) }
            if child.children.contains(where: { $0 === speedLabel }) { child.position = CGPoint(x: 360, y: size.height - 50) }
            if child.children.contains(where: { $0 === timeLabel }) { child.position = CGPoint(x: size.width - 190, y: size.height - 50) }
            if child.children.contains(where: { $0 === scoreLabel }) { child.position = CGPoint(x: size.width - 90, y: size.height - 50) }
        }
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
        speakerLabel.text = soundOn ? "🔊 ON" : "🔇 OFF"
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
    func restartGame() { score = 25; level = 1; prepareGame() }
    func makeBrickFall(_ brick: SKNode) {
        brick.name = nil
        brick.physicsBody?.isDynamic = true
        brick.physicsBody?.collisionBitMask = 0; brick.physicsBody?.categoryBitMask = 0; brick.physicsBody?.contactTestBitMask = 0
        brick.physicsBody?.velocity = CGVector(dx: CGFloat.random(in: -80...80), dy: -350)
        brick.physicsBody?.angularVelocity = CGFloat.random(in: -6...6)
        brick.run(.sequence([.wait(forDuration: 2.0), .removeFromParent()]))
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
        for n in nodes(at: loc) {
            if n.name == "statusButton" || n.parent?.name == "statusButton" { handleStatusToggle(); return }
            if n.name == "speakerButton" || n.parent?.name == "speakerButton" { toggleSound(); return }
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
