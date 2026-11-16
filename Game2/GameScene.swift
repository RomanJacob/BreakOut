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
    var startSpeedPercent = 100
    var hiddenRowsRemaining = 0
    let maxVisibleRows = 7
    let bricksPerRow = 8
    
    var isPlaying = false
    var gamePaused = false
    var isGameOver = false
    var startTime: TimeInterval = 0
    // Multi-ball: level 1 = 1 bold, level 2 = 2 bolde, level 3 = 3 bolde, så forfra (4 = 1, 5 = 2, 6 = 3 ...)
    // Point trækkes KUN når alle bolde er misset.
    var extraBalls: [SKShapeNode] = []
    var allBalls: [SKShapeNode] { [ball] + extraBalls }
    var activeBalls: [SKShapeNode] { allBalls.filter { !$0.isHidden } }
    func ballCount(for lvl: Int) -> Int { (max(lvl, 1) - 1) % 3 + 1 }
    func ballsText(_ n: Int) -> String { n == 1 ? "1 BALL" : "\(n) BALLS" }
    /// x3 point så længe alle 3 bolde er i spil på et 3-bolde-level, ellers x1
    func pointMultiplier() -> Int { (allBalls.count == 3 && activeBalls.count == 3) ? 3 : 1 }
    /// Lægger point til (ganget med multiplier) og viser "+N" der hvor det skete
    func addPoints(_ base: Int, at pos: CGPoint) {
        let m = pointMultiplier()
        let pts = base * m
        score += pts
        if score > highScore { highScore = score; UserDefaults.standard.set(highScore, forKey: "HighScore") }
        let pop = SKLabelNode(fontNamed: "Menlo-Bold")
        pop.text = m > 1 ? "+\(pts) x\(m)" : "+\(pts)"
        pop.fontSize = m > 1 ? 18 : 13
        pop.fontColor = m > 1 ? .systemYellow : .white
        pop.position = CGPoint(x: pos.x, y: pos.y + 14); pop.zPosition = 30
        addChild(pop)
        pop.run(.sequence([.group([.moveBy(x: 0, y: 40, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }
    // Farver bolden skifter imellem, hver gang den rammer pladen
    let ballColors: [SKColor] = [.systemYellow, .cyan, .systemPink, .systemGreen, .systemOrange, .white, .systemPurple]
    
    let baseSpeed: CGFloat = 125
    let speedStep: CGFloat = 0.08
    // Ny rækkefølge - rød og pink er aldrig naboer, så de ligner ikke 2 ens røde rækker
    let brickColors: [SKColor] = [.systemRed, .systemOrange, .systemYellow, .systemPink, .systemGreen, .cyan, .systemPurple]
    
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
    var speakerIcon: SKSpriteNode!
    var speakerOnTexture: SKTexture!
    var speakerOffTexture: SKTexture!
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
        let savedSpeed = UserDefaults.standard.integer(forKey: "StartSpeedPercent")
        startSpeedPercent = savedSpeed == 0 ? 100 : savedSpeed
        
        backgroundColor = .black
        updateBackground()
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = .zero
        view.window?.acceptsMouseMovedEvents = true
        
        createWalls()
        
        configureBallPhysics(ball)
        addChild(ball)

        // 3D-plade: metal-look med glans og skygge
        paddle.texture = bevelTexture(size: paddle.size, color: SKColor(calibratedRed: 0.72, green: 0.85, blue: 1.0, alpha: 1), radius: 10)
        let paddleShadow = SKSpriteNode(color: .black, size: paddle.size)
        paddleShadow.alpha = 0.4; paddleShadow.position = CGPoint(x: 4, y: -5); paddleShadow.zPosition = -1
        paddle.addChild(paddleShadow)
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
    
    // MARK: - 3D-look (teksturer med lys, skygge og glans)
    var textureCache: [String: SKTexture] = [:]
    /// Afrundet "klods" med lys top, mørk bund, glans-stribe og mørk kant
    func bevelTexture(size: CGSize, color: SKColor, radius: CGFloat) -> SKTexture {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let key = String(format: "bevel-%.0fx%.0f-%.0f-%.3f-%.3f-%.3f", size.width, size.height, radius,
                         rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        if let t = textureCache[key] { return t }
        let img = NSImage(size: size, flipped: false) { rect in
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: radius, yRadius: radius)
            let light = rgb.blended(withFraction: 0.5, of: .white) ?? rgb
            let dark = rgb.blended(withFraction: 0.45, of: .black) ?? rgb
            NSGradient(colors: [light, rgb, dark], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)?.draw(in: body, angle: -90)
            // glans-stribe foroven
            let shineRect = NSRect(x: rect.minX + 3, y: rect.maxY - rect.height * 0.42, width: rect.width - 6, height: rect.height * 0.3)
            let shine = NSBezierPath(roundedRect: shineRect, xRadius: radius * 0.7, yRadius: radius * 0.7)
            NSColor(white: 1, alpha: 0.35).setFill(); shine.fill()
            // mørk kant
            NSColor(white: 0, alpha: 0.5).setStroke(); body.lineWidth = 1.5; body.stroke()
            return true
        }
        let tex = SKTexture(image: img)
        textureCache[key] = tex
        return tex
    }
    /// Gråtone-kugle (lys øverst til venstre) – farves af fillColor, så bolden ligner en 3D-kugle
    lazy var sphereTexture: SKTexture = {
        let size = CGSize(width: 64, height: 64)
        let img = NSImage(size: size, flipped: false) { rect in
            let g = NSGradient(colors: [.white, NSColor(white: 0.85, alpha: 1), NSColor(white: 0.35, alpha: 1)],
                               atLocations: [0, 0.35, 1], colorSpace: .deviceRGB)
            g?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
            return true
        }
        return SKTexture(image: img)
    }()
    /// Baggrund: mørk blå gradient med svagt lys foroven
    func makeBackgroundTexture(size: CGSize) -> SKTexture {
        let img = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.24, alpha: 1),
                                NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.09, alpha: 1)])?.draw(in: rect, angle: -90)
            NSGradient(colors: [NSColor(calibratedRed: 0.3, green: 0.4, blue: 1, alpha: 0.18), .clear])?
                .draw(in: NSBezierPath(ovalIn: NSRect(x: rect.midX - rect.width*0.6, y: rect.maxY - rect.height*0.55,
                                                      width: rect.width*1.2, height: rect.height*1.0)),
                      relativeCenterPosition: NSPoint(x: 0, y: 0.3))
            return true
        }
        return SKTexture(image: img)
    }
    func updateBackground() {
        guard size.width > 1, size.height > 1 else { return }
        let bg: SKSpriteNode
        if let existing = childNode(withName: "bg3d") as? SKSpriteNode { bg = existing }
        else { bg = SKSpriteNode(); bg.name = "bg3d"; bg.zPosition = -100; addChild(bg) }
        bg.texture = makeBackgroundTexture(size: size)
        bg.size = size
        bg.position = CGPoint(x: size.width/2, y: size.height/2)
    }
    /// Firkantet 3D-klods med skygge
    func makeBlockBrick(color: SKColor, size bsize: CGSize) -> SKSpriteNode {
        let brick = SKSpriteNode(texture: bevelTexture(size: bsize, color: color, radius: 5), size: bsize)
        brick.color = color            // bruges af eksplosion og fald-animation
        brick.colorBlendFactor = 0
        let shadow = SKSpriteNode(color: .black, size: bsize)
        shadow.alpha = 0.4; shadow.position = CGPoint(x: 4, y: -4); shadow.zPosition = -1
        brick.addChild(shadow)
        return brick
    }

    // MARK: - Bolde
    func configureBallPhysics(_ b: SKShapeNode) {
        // Selve noden er usynlig og bærer fysikken; "skin" er det man ser,
        // så vi kan gøre bolden flad/oval uden at ændre fysik-kroppen.
        b.fillColor = .clear
        b.strokeColor = .clear
        if b.childNode(withName: "skin") == nil {
            let shadow = SKShapeNode(circleOfRadius: 19)
            shadow.fillColor = .black; shadow.strokeColor = .clear; shadow.alpha = 0.35
            shadow.position = CGPoint(x: 5, y: -6); shadow.zPosition = -1
            b.addChild(shadow)
            let skin = SKShapeNode(circleOfRadius: 20)
            skin.name = "skin"; skin.strokeColor = .clear; skin.fillColor = .systemYellow
            skin.fillTexture = sphereTexture
            let shine = SKShapeNode(circleOfRadius: 6)
            shine.fillColor = SKColor(white: 1, alpha: 0.55); shine.strokeColor = .clear
            shine.position = CGPoint(x: -6, y: 7)
            skin.addChild(shine)
            b.addChild(skin)
        }
        b.physicsBody = SKPhysicsBody(circleOfRadius: 20)
        b.physicsBody?.categoryBitMask = PhysicsCategory.ball
        b.physicsBody?.restitution = 1
        b.physicsBody?.friction = 0
        b.physicsBody?.linearDamping = 0
        b.physicsBody?.allowsRotation = false
    }
    /// Sørger for at der er det rigtige antal bolde til nuværende level
    func configureBallsForLevel() {
        let wanted = ballCount(for: level) - 1
        while extraBalls.count > wanted { extraBalls.removeLast().removeFromParent() }
        while extraBalls.count < wanted {
            let b = SKShapeNode(circleOfRadius: 20)
            configureBallPhysics(b)
            addChild(b)
            extraBalls.append(b)
        }
    }
    func centerBalls() {
        let n = allBalls.count
        for (i, b) in allBalls.enumerated() {
            let offset = n > 1 ? (CGFloat(i) - CGFloat(n - 1) / 2) * 80 : 0
            b.position = CGPoint(x: size.width/2 + offset, y: size.height/2)
        }
    }
    func isArmed(_ b: SKNode) -> Bool { (b.userData?["armed"] as? Bool) ?? false }
    func skin(_ b: SKNode) -> SKShapeNode? { b.childNode(withName: "skin") as? SKShapeNode }
    func setBallColor(_ b: SKShapeNode, _ c: SKColor) { skin(b)?.fillColor = c }
    /// Flad "squash" når bolden rammer pladen
    func squash(_ b: SKShapeNode) {
        guard let sk = skin(b) else { return }
        sk.removeAction(forKey: "squash")
        sk.zRotation = 0; sk.xScale = 1.55; sk.yScale = 0.5
        let back = SKAction.group([.scaleX(to: 1.0, duration: 0.22), .scaleY(to: 1.0, duration: 0.22)])
        back.timingMode = .easeOut
        sk.run(back, withKey: "squash")
    }
    /// Oval i faldretningen når bolden er på vej ned, rund på vej op
    func updateBallShape(_ b: SKShapeNode) {
        guard let sk = skin(b), sk.action(forKey: "squash") == nil, let v = b.physicsBody?.velocity else { return }
        let speed = hypot(v.dx, v.dy)
        var target: CGFloat = 1.0
        if v.dy < 0 && speed > 1 { target = 1.0 + min(0.45, speed / 700) }
        let stretch = sk.xScale + (target - sk.xScale) * 0.2
        sk.xScale = stretch; sk.yScale = 1.0 / stretch
        if speed > 1 { sk.zRotation = atan2(v.dy, v.dx) }
    }
    /// Lægger en bold "ud af spil" (misset), uden at ændre point
    func parkBall(_ b: SKShapeNode) {
        b.physicsBody?.velocity = .zero
        disarmBall(b)
        b.isHidden = true
        b.position = CGPoint(x: size.width/2, y: size.height/2)
    }
    func pauseBalls() {
        for b in allBalls {
            if b.userData == nil { b.userData = NSMutableDictionary() }
            b.userData?["pv"] = NSValue(point: NSPoint(x: b.physicsBody?.velocity.dx ?? 0, y: b.physicsBody?.velocity.dy ?? 0))
            b.physicsBody?.velocity = .zero
        }
    }
    func resumeBalls() {
        for b in allBalls {
            if let v = (b.userData?["pv"] as? NSValue)?.pointValue { b.physicsBody?.velocity = CGVector(dx: v.x, dy: v.y) }
        }
    }
    func launchAllBalls(atSpeed speed: CGFloat) {
        for b in allBalls { launchBallAtSpeed(speed, b) }
    }

    func createWalls() {
        for n in children where n.name == "leftWall" || n.name == "rightWall" || n.name == "topWall" { n.removeFromParent() }
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
        updateBackground()
        createWalls()
        layoutHUD()
        paddle.position.y = 80
        if !isPlaying { centerBalls() }
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
        speakerLabel.isHidden = true; speakerButton.addChild(speakerLabel)
        
        // SF Symbols speaker icons - typical 🔊 and 🔇 with X
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .bold, scale: .medium)
        if let onImg = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
            onImg.isTemplate = true
            speakerOnTexture = SKTexture(image: onImg)
        } else {
            let label = SKLabelNode(text: "🔊"); label.fontSize = 18
            let v = SKView(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
            speakerOnTexture = v.texture(from: label) ?? SKTexture()
        }
        if let offImg = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
            offImg.isTemplate = true
            speakerOffTexture = SKTexture(image: offImg)
        } else {
            let label = SKLabelNode(text: "🔇"); label.fontSize = 18
            let v = SKView(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
            speakerOffTexture = v.texture(from: label) ?? SKTexture()
        }
        let initialTex = soundOn ? speakerOnTexture : speakerOffTexture
        speakerIcon = SKSpriteNode(texture: initialTex, color: .white, size: CGSize(width: 22, height: 22))
        speakerIcon.colorBlendFactor = 1.0
        speakerIcon.position = CGPoint(x: 25, y: 16)
        speakerIcon.name = "speakerIcon"
        speakerButton.addChild(speakerIcon)
        
        levelBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 85, height: 32), cornerRadius: 8)
        levelBox.fillColor = SKColor(white: 0.2, alpha: 0.9); levelBox.strokeColor = .systemPurple
        levelBox.name = "levelBox"; addChild(levelBox)
        levelLabel = SKLabelNode(fontNamed: "Menlo-Bold"); levelLabel.fontSize = 11; levelLabel.fontColor = .systemPurple
        levelLabel.position = CGPoint(x: 42, y: 8); levelBox.addChild(levelLabel)
        
        highBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        highBox.fillColor = SKColor(white: 0.2, alpha: 0.9); highBox.strokeColor = .white
        addChild(highBox)
        highScoreLabel = SKLabelNode(fontNamed: "Menlo-Bold"); highScoreLabel.fontSize = 10; highScoreLabel.fontColor = .cyan
        highScoreLabel.position = CGPoint(x: 47, y: 8); highBox.addChild(highScoreLabel)
        
        speedBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        speedBox.fillColor = SKColor(white: 0.2, alpha: 0.9); speedBox.strokeColor = .yellow
        speedBox.name = "speedBox"; addChild(speedBox)
        speedLabel = SKLabelNode(fontNamed: "Menlo-Bold"); speedLabel.fontSize = 10; speedLabel.fontColor = .yellow
        speedLabel.position = CGPoint(x: 47, y: 8); speedBox.addChild(speedLabel)
        
        resetButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 95, height: 32), cornerRadius: 8)
        resetButton.fillColor = SKColor(white: 0.25, alpha: 0.9); resetButton.strokeColor = .systemRed
        resetButton.name = "resetButton"; addChild(resetButton)
        resetButtonLabel = SKLabelNode(fontNamed: "Menlo-Bold"); resetButtonLabel.fontSize = 10; resetButtonLabel.fontColor = .systemRed
        resetButtonLabel.text = "RESET ALL"; resetButtonLabel.position = CGPoint(x: 47, y: 8); resetButton.addChild(resetButtonLabel)
        
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
    
    // MARK: - Trekant-klodser
    // Level 1-2: almindelige firkanter.
    // Level 3:   trekanter skiftevis spids OP/NED (lodret), der griber ind i hinanden.
    // Fra level 4: BLANDET – rækkerne skifter mellem op/ned-trekanter,
    //              højre/venstre-trekanter og firkanter (rækkefølgen skifter med level).
    enum RowMode { case squares, upDown, leftRight }
    func rowMode(level lvl: Int, row r: Int) -> RowMode {
        if lvl < 3 { return .squares }
        if lvl == 3 { return .upDown }
        let mix: [RowMode] = [.upDown, .leftRight, .squares]
        return mix[(r + lvl) % mix.count]
    }
    func rowHeight(_ mode: RowMode) -> CGFloat {
        switch mode {
        case .squares: return 28
        case .upDown: return 36
        case .leftRight: return 42
        }
    }
    // NB: punkterne skal være mod uret (counter-clockwise), ellers fejler SKPhysicsBody(polygonFrom:)
    func makeTriangleBrick(points: [CGPoint], color: SKColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.addLines(between: points); path.closeSubpath()
        let tri = SKShapeNode(path: path)
        tri.fillColor = color
        tri.strokeColor = .black
        tri.lineWidth = 2
        tri.name = "brick"
        // 3D: mørk "side" bagved (ekstrudering) og lys glans-flade ovenpå
        let depth = SKShapeNode(path: path)
        depth.fillColor = color.blended(withFraction: 0.6, of: .black) ?? .black
        depth.strokeColor = .clear
        depth.position = CGPoint(x: 3, y: -4); depth.zPosition = -1
        tri.addChild(depth)
        let cx = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let cy = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let hiPath = CGMutablePath()
        hiPath.addLines(between: points.map { CGPoint(x: cx + ($0.x - cx) * 0.55, y: cy + ($0.y - cy) * 0.55 + 2) })
        hiPath.closeSubpath()
        let hi = SKShapeNode(path: hiPath)
        hi.fillColor = SKColor(white: 1, alpha: 0.25); hi.strokeColor = .clear; hi.zPosition = 1
        tri.addChild(hi)
        tri.physicsBody = SKPhysicsBody(polygonFrom: path)
        tri.physicsBody?.isDynamic = false
        tri.physicsBody?.categoryBitMask = PhysicsCategory.brick
        return tri
    }
    func addBrickRow(row r: Int, y: CGFloat, color: SKColor, mode: RowMode, startX: CGFloat, totalW: CGFloat) {
        switch mode {
        case .squares:
            let brickW: CGFloat = 75, brickH: CGFloat = 22, pad: CGFloat = 6
            for c in 0..<bricksPerRow {
                let brick = makeBlockBrick(color: color, size: CGSize(width: brickW, height: brickH))
                brick.position = CGPoint(x: startX + CGFloat(c)*(brickW+pad) + brickW/2, y: y)
                brick.name = "brick"
                brick.physicsBody = SKPhysicsBody(rectangleOf: brick.size)
                brick.physicsBody?.isDynamic = false
                brick.physicsBody?.categoryBitMask = PhysicsCategory.brick
                addChild(brick)
            }
        case .upDown:
            // 15 trekanter pr. række, halv bredde imellem -> de griber ind i hinanden ▲▼▲▼▲
            let w: CGFloat = 80, h: CGFloat = 30, gap: CGFloat = 3
            let count = bricksPerRow * 2 - 1
            let step = (totalW - w) / CGFloat(count - 1)
            for i in 0..<count {
                let up = (i + r) % 2 == 0
                let hw = w/2 - gap, hh = h/2 - gap/2
                let pts = up ? [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh), CGPoint(x: 0, y: hh)]
                             : [CGPoint(x: -hw, y: hh), CGPoint(x: 0, y: -hh), CGPoint(x: hw, y: hh)]
                // skiftevis lys/mørk nuance, så hver trekant kan ses
                let shade = up ? color : (color.blended(withFraction: 0.35, of: .black) ?? color)
                let tri = makeTriangleBrick(points: pts, color: shade)
                tri.position = CGPoint(x: startX + w/2 + CGFloat(i) * step, y: y)
                addChild(tri)
            }
        case .leftRight:
            // Spids mod højre/venstre, spejlet om midten ▶◀
            let w: CGFloat = 70, h: CGFloat = 36
            let step = (totalW - w) / CGFloat(bricksPerRow - 1)
            for c in 0..<bricksPerRow {
                let right = (c + r) % 2 == 0
                let hw = w/2 - 3, hh = h/2 - 2
                let pts = right ? [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: 0), CGPoint(x: -hw, y: hh)]
                                : [CGPoint(x: hw, y: -hh), CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: 0)]
                let shade = right ? color : (color.blended(withFraction: 0.35, of: .black) ?? color)
                let tri = makeTriangleBrick(points: pts, color: shade)
                tri.position = CGPoint(x: startX + w/2 + CGFloat(c) * step, y: y)
                addChild(tri)
            }
        }
    }

    // MARK: - Lodrette klodser (random)
    // Level 5, 10, 15 ...: stående klodser placeret tilfældigt – nyt mønster hver gang
    func isVerticalLevel(_ lvl: Int) -> Bool { lvl >= 5 && lvl % 5 == 0 }
    func createVerticalBricks(rows: Int) {
        for n in children where n.name == "brick" { n.removeFromParent() }
        let brickW: CGFloat = 22, brickH: CGFloat = 60
        let areaW: CGFloat = 8*75 + 7*6
        let startX = (size.width - areaW)/2
        let topY = size.height - 110 - brickH/2 + 11
        let bands = max(2, min(rows, 4))          // antal "etager" med lodrette klodser
        let slotW: CGFloat = 32
        let slots = Int(areaW / slotW)
        var placed = 0
        for band in 0..<bands {
            let y = topY - CGFloat(band) * (brickH + 12)
            for slot in 0..<slots {
                // ca. 45% chance for en klods i hver plads, så det bliver tilfældigt og luftigt
                let mustPlace = placed < 10 && band == bands - 1 && slot >= slots - (10 - placed)
                guard mustPlace || Double.random(in: 0..<1) < 0.45 else { continue }
                let color = brickColors.randomElement() ?? .systemRed
                let brick = makeBlockBrick(color: color, size: CGSize(width: brickW, height: brickH))
                let jitter = CGFloat.random(in: -4...4)
                brick.position = CGPoint(x: startX + slotW/2 + CGFloat(slot) * slotW + jitter, y: y)
                brick.name = "brick"
                brick.physicsBody = SKPhysicsBody(rectangleOf: brick.size)
                brick.physicsBody?.isDynamic = false
                brick.physicsBody?.categoryBitMask = PhysicsCategory.brick
                addChild(brick)
                placed += 1
            }
        }
    }

    func createBricks(rows: Int) {
        if isVerticalLevel(level) { createVerticalBricks(rows: rows); return }
        for n in children where n.name == "brick" { n.removeFromParent() }
        let brickW: CGFloat = 75, pad: CGFloat = 6
        let totalW = CGFloat(bricksPerRow)*brickW + CGFloat(bricksPerRow-1)*pad
        let startX = (size.width - totalW)/2
        var y = size.height - 110

        // 100% garanti: aldrig 2 rækker med samme farve i samme wave
        // og hver række forskellig fra over/under
        var colorOrder = Array(0..<brickColors.count)
        let offset = level % brickColors.count
        if offset > 0 {
            colorOrder = Array(colorOrder[offset...] + colorOrder[..<offset])
        }
        var lastIndex: Int? = nil
        var lastMode: RowMode? = nil
        for r in 0..<rows {
            var idx = colorOrder[r % colorOrder.count]
            if let last = lastIndex, idx == last {
                idx = (idx + 1) % brickColors.count
            }
            lastIndex = idx
            let rowColor = brickColors[idx]
            let mode = rowMode(level: level, row: r)
            // række-afstand: halvdelen af denne + halvdelen af forrige rækkes højde
            if let lm = lastMode { y -= (rowHeight(lm) + rowHeight(mode)) / 2 }
            lastMode = mode
            addBrickRow(row: r, y: y, color: rowColor, mode: mode, startX: startX, totalW: totalW)
        }
    }

    func setupLevel(_ lvl: Int) {
        level = lvl
        UserDefaults.standard.set(level, forKey: "CurrentLevel")
        let visible = min(lvl, maxVisibleRows)
        hiddenRowsRemaining = lvl - visible
        createBricks(rows: visible)
        configureBallsForLevel()
        updateHUD()
    }
    
    func disarmBall(_ b: SKShapeNode) {
        if b.userData == nil { b.userData = NSMutableDictionary() }
        b.userData?["armed"] = false
        b.physicsBody?.collisionBitMask = PhysicsCategory.paddle | PhysicsCategory.wall
        b.physicsBody?.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.wall
        setBallColor(b, .systemGray)
    }
    func armBall(_ b: SKShapeNode) {
        if b.userData == nil { b.userData = NSMutableDictionary() }
        b.userData?["armed"] = true
        b.physicsBody?.collisionBitMask = PhysicsCategory.paddle | PhysicsCategory.wall | PhysicsCategory.brick
        b.physicsBody?.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.brick | PhysicsCategory.wall
        // Ny farve hver gang bolden rammer pladen
        let idx = ((b.userData?["colorIdx"] as? Int) ?? -1) + 1
        b.userData?["colorIdx"] = idx
        setBallColor(b, ballColors[idx % ballColors.count])
    }
    func getStartSpeed() -> CGFloat { return baseSpeed * CGFloat(startSpeedPercent) / 100.0 }
    func currentSpeed() -> CGFloat {
        let diff = CGFloat(score - 25) / 10.0
        return getStartSpeed() * max(0.5, min(1.0 + diff*speedStep, 2.5)) * (1.0 + CGFloat(level)*0.05)
    }
    func playHitSound() { if soundOn { NSSound(named: "Pop")?.play() } }
    func playMissSound() { if soundOn { NSSound(named: "Basso")?.play() } }
    func updateHUD() {
        let m = pointMultiplier()
        scoreLabel.text = m > 1 ? String(format: "Pts: %02d x%d", score, m) : String(format: "Points: %02d", score)
        scoreLabel.fontColor = m > 1 ? .systemOrange : .systemYellow
        highScoreLabel.text = String(format: "High: %02d", highScore)
        // Viser din indstilling → den aktuelle fart (som stiger med point og level)
        let live = Int((currentSpeed() / baseSpeed * 100).rounded())
        speedLabel.text = "Spd \(startSpeedPercent)%→\(live)%"
        speakerIcon?.texture = soundOn ? speakerOnTexture : speakerOffTexture
        if let icon = speakerIcon {
            icon.color = soundOn ? .white : .systemRed
            icon.colorBlendFactor = 1.0
        }
        let ballsTag = allBalls.count > 1 ? " " + String(repeating: "●", count: allBalls.count) : ""
        if hiddenRowsRemaining > 0 { levelLabel.text = "Level: \(level) (+\(hiddenRowsRemaining))\(ballsTag)" }
        else { levelLabel.text = "Level: \(level)\(ballsTag)" }
        levelLabel.fontSize = (levelLabel.text?.count ?? 0) > 12 ? 9 : 11
        if isGameOver { statusButtonLabel.text = "START"; statusButton.fillColor = .systemGreen }
        else if isPlaying { statusButtonLabel.text = "PLAYING"; statusButton.fillColor = .systemGreen }
        else if gamePaused { statusButtonLabel.text = "PAUSED"; statusButton.fillColor = .systemYellow }
        else { statusButtonLabel.text = "START"; statusButton.fillColor = .systemGreen }
    }
    func prepareGame() {
        isPlaying = false; gamePaused = false; isGameOver = false
        setupLevel(level)
        centerBalls()
        for b in allBalls { disarmBall(b); b.physicsBody?.velocity = .zero; b.isHidden = false }
        gameOverLabel.text = allBalls.count > 1 ? "\(ballsText(allBalls.count))! Press SpaceBar to Play" : "Press SpaceBar to Play"
        gameOverLabel.fontColor = .white; gameOverLabel.isHidden = false
        updateHUD()
    }
    func launchBall(_ b: SKShapeNode) {
        launchBallAtSpeed(currentSpeed(), b)
    }
    func launchBallAtSpeed(_ fixedSpeed: CGFloat, _ b: SKShapeNode) {
        disarmBall(b)
        let angle = CGFloat.random(in: 35.0...145.0) * .pi / 180
        b.physicsBody?.velocity = CGVector(dx: cos(angle)*fixedSpeed, dy: sin(angle)*fixedSpeed)
    }
    func handleStatusToggle() {
        if isGameOver { restartGame(); return }
        if isPlaying {
            gamePaused = true; isPlaying = false
            pauseBalls()
            gameOverLabel.text = "PAUSED"; gameOverLabel.fontColor = .yellow; gameOverLabel.isHidden = false
        } else {
            if gamePaused {
                gamePaused = false; isPlaying = true
                resumeBalls()
                gameOverLabel.isHidden = true
            } else {
                isPlaying = true; gameOverLabel.isHidden = true; launchAllBalls(atSpeed: getStartSpeed())
            }
        }
        updateHUD()
    }
    func toggleSound() { soundOn.toggle(); UserDefaults.standard.set(soundOn, forKey: "SoundOn"); updateHUD(); if soundOn { playHitSound() } }
    func restartGame() { score = 25; prepareGame() }
    
    func promptForLevel() {
        if isPlaying { gamePaused = true; isPlaying = false; pauseBalls() }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Change Level"; alert.informativeText = "Enter level number (1-99):"
            alert.alertStyle = .informational; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24)); tf.stringValue = "\(self.level)"
            alert.accessoryView = tf; alert.window.initialFirstResponder = tf
            if alert.runModal() == .alertFirstButtonReturn, let nl = Int(tf.stringValue), (1...99).contains(nl) {
                self.level = nl; UserDefaults.standard.set(nl, forKey: "CurrentLevel"); self.score = 25; self.prepareGame()
            } else if self.gamePaused {
                self.gamePaused = false; self.isPlaying = true; self.resumeBalls(); self.gameOverLabel.isHidden = true; self.updateHUD()
            }
        }
    }
    /// Giver alle bolde den nye fart med det samme (samme retning), også hvis spillet er sat på pause
    func applyNewSpeedToBalls() {
        let speed = currentSpeed()
        for b in activeBalls {
            if let pv = (b.userData?["pv"] as? NSValue)?.pointValue, gamePaused {
                let len = hypot(pv.x, pv.y)
                if len > 1 { b.userData?["pv"] = NSValue(point: NSPoint(x: pv.x / len * speed, y: pv.y / len * speed)) }
            } else if let v = b.physicsBody?.velocity {
                let len = hypot(v.dx, v.dy)
                if len > 1 { b.physicsBody?.velocity = CGVector(dx: v.dx / len * speed, dy: v.dy / len * speed) }
            }
        }
    }
    func promptForSpeed() {
        if isPlaying { gamePaused = true; isPlaying = false; pauseBalls() }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Change Start Speed"; alert.informativeText = "Enter start speed in % (50-300%):\n100% = 125, 150% = 187, 200% = 250"
            alert.alertStyle = .informational; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24)); tf.stringValue = "\(self.startSpeedPercent)"
            alert.accessoryView = tf; alert.window.initialFirstResponder = tf
            if alert.runModal() == .alertFirstButtonReturn {
                // Tillad "150", "150%" og " 150 " – og hold værdien inden for 50-300
                let raw = tf.stringValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let typed = Int(raw) {
                    let ns = min(max(typed, 50), 300)
                    self.startSpeedPercent = ns
                    UserDefaults.standard.set(ns, forKey: "StartSpeedPercent")
                    self.applyNewSpeedToBalls()
                    self.updateHUD()
                }
            }
            if self.gamePaused { self.gamePaused = false; self.isPlaying = true; self.resumeBalls(); self.gameOverLabel.isHidden = true; self.updateHUD() }
        }
    }
    func confirmResetAll() {
        if isPlaying { gamePaused = true; isPlaying = false; pauseBalls() }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Reset All Progress?"; alert.informativeText = "This will reset score, high score, level and speed to defaults. This cannot be undone."
            alert.alertStyle = .warning; alert.addButton(withTitle: "Reset All"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { self.resetAllProgress() }
            else if self.gamePaused { self.gamePaused = false; self.isPlaying = true; self.resumeBalls(); self.gameOverLabel.isHidden = true; self.updateHUD() }
        }
    }
    func resetAllProgress() {
        score = 25; highScore = 0; level = 1; startSpeedPercent = 100
        UserDefaults.standard.removeObject(forKey: "HighScore")
        UserDefaults.standard.removeObject(forKey: "CurrentLevel")
        UserDefaults.standard.removeObject(forKey: "StartSpeedPercent")
        UserDefaults.standard.set(0, forKey: "HighScore"); UserDefaults.standard.set(1, forKey: "CurrentLevel"); UserDefaults.standard.set(100, forKey: "StartSpeedPercent")
        prepareGame()
    }
    // MARK: - Eksplosion
    /// Lille eksplosion: hvidt glimt, en trykbølge-ring og gnister/skår i klodsens farve
    func explode(at pos: CGPoint, color: SKColor) {
        // 1) glimt
        let flash = SKShapeNode(circleOfRadius: 18)
        flash.position = pos; flash.zPosition = 20
        flash.fillColor = .white; flash.strokeColor = .clear; flash.glowWidth = 12
        addChild(flash)
        flash.run(.sequence([.group([.scale(to: 2.2, duration: 0.15), .fadeOut(withDuration: 0.18)]), .removeFromParent()]))
        // 2) trykbølge
        let ring = SKShapeNode(circleOfRadius: 10)
        ring.position = pos; ring.zPosition = 19
        ring.fillColor = .clear; ring.strokeColor = color.blended(withFraction: 0.4, of: .white) ?? color
        ring.lineWidth = 4; ring.glowWidth = 4
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 6, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        // 3) gnister og skår
        for i in 0..<18 {
            let spark: SKShapeNode
            if i % 3 == 0 {
                let p = CGMutablePath()
                p.addLines(between: [CGPoint(x: -5, y: -4), CGPoint(x: 5, y: -4), CGPoint(x: 0, y: 6)]); p.closeSubpath()
                spark = SKShapeNode(path: p)
                spark.fillColor = color
            } else {
                spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...4))
                spark.fillColor = i % 2 == 0 ? .white : (color.blended(withFraction: 0.3, of: .yellow) ?? color)
                spark.glowWidth = 2
            }
            spark.strokeColor = .clear
            spark.position = pos; spark.zPosition = 21
            addChild(spark)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist = CGFloat.random(in: 40...120)
            let dur = TimeInterval(CGFloat.random(in: 0.35...0.7))
            let move = SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist - 20, duration: dur)
            move.timingMode = .easeOut
            spark.run(.sequence([
                .group([move, .rotate(byAngle: CGFloat.random(in: -10...10), duration: dur),
                        .fadeOut(withDuration: dur), .scale(to: 0.3, duration: dur)]),
                .removeFromParent()
            ]))
        }
    }

    func makeBrickFall(_ brick: SKNode) {
        // Eksplosion først – uanset klodstype
        let hitColor = (brick as? SKShapeNode)?.fillColor ?? (brick as? SKSpriteNode)?.color ?? .white
        explode(at: brick.position, color: hitColor)

        if let tri = brick as? SKShapeNode {
            // Trekant falder, roterer og skifter farve gennem regnbuen
            tri.name = nil; tri.physicsBody = nil; tri.zPosition = 10
            let startIdx = brickColors.firstIndex(where: { $0.isEqual(tri.fillColor) }) ?? Int.random(in: 0..<brickColors.count)
            let total: CGFloat = 1.8
            let colorCycle = SKAction.customAction(withDuration: TimeInterval(total)) { [colors = brickColors] node, elapsed in
                guard let shape = node as? SKShapeNode else { return }
                let pos = elapsed / total * CGFloat(colors.count) * 1.5
                let i = Int(pos) % colors.count
                let frac = pos - floor(pos)
                let c1 = colors[(startIdx + i) % colors.count]
                let c2 = colors[(startIdx + i + 1) % colors.count]
                shape.fillColor = c1.blended(withFraction: frac, of: c2) ?? c1
            }
            let fall = SKAction.group([
                .moveBy(x: CGFloat.random(in: -80...80), y: -(tri.position.y + 60), duration: TimeInterval(total)),
                .rotate(byAngle: CGFloat.random(in: 8...14) * (Bool.random() ? 1 : -1), duration: TimeInterval(total)),
                .sequence([.wait(forDuration: 0.9), .fadeOut(withDuration: 0.9)]),
                .scale(to: 0.4, duration: TimeInterval(total))
            ])
            fall.timingMode = .easeIn
            tri.run(.sequence([.group([fall, colorCycle]), .removeFromParent()]))
            return
        }
        guard let brickSprite = brick as? SKSpriteNode else { brick.removeFromParent(); return }
        brick.name = nil
        let originalColor = brickSprite.color
        let originalSize = brickSprite.size
        let currentIdx = brickColors.firstIndex(where: { $0.isEqual(originalColor) }) ?? 0
        let nextLayerColor: SKColor
        if level <= 1 { nextLayerColor = originalColor }
        else { nextLayerColor = brickColors[(currentIdx + 1) % brickColors.count] }
        let nextTopColor = nextLayerColor.blended(withFraction: 0.35, of: .white) ?? nextLayerColor
        let nextSideColor = nextLayerColor.blended(withFraction: 0.35, of: .black) ?? nextLayerColor
        let container = SKNode(); container.position = brick.position; container.zPosition = 10; addChild(container); brick.removeFromParent()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: originalSize.width*0.9, height: 12))
        shadow.fillColor = .black; shadow.strokeColor = .clear; shadow.alpha = 0.35; shadow.position = CGPoint(x: 0, y: -size.height/2 + 80); shadow.zPosition = -1; container.addChild(shadow)
        let front = SKSpriteNode(color: originalColor, size: originalSize); front.zPosition = 1; container.addChild(front)
        let topEdge = SKSpriteNode(color: originalColor.blended(withFraction: 0.35, of: .white) ?? originalColor, size: CGSize(width: originalSize.width, height: 6))
        topEdge.position = CGPoint(x: 0, y: originalSize.height/2); topEdge.zPosition = 0; container.addChild(topEdge)
        let sideEdge = SKSpriteNode(color: originalColor.blended(withFraction: 0.35, of: .black) ?? originalColor, size: CGSize(width: 6, height: originalSize.height))
        sideEdge.position = CGPoint(x: originalSize.width/2, y: 0); sideEdge.zPosition = 0; container.addChild(sideEdge)
        container.physicsBody = SKPhysicsBody(rectangleOf: originalSize)
        container.physicsBody?.isDynamic = true; container.physicsBody?.collisionBitMask = 0; container.physicsBody?.categoryBitMask = 0; container.physicsBody?.contactTestBitMask = 0
        container.physicsBody?.velocity = CGVector(dx: CGFloat.random(in: -120.0...120.0), dy: CGFloat.random(in: -380.0...(-280.0)))
        container.physicsBody?.angularVelocity = CGFloat.random(in: 4.0...9.0) * (Bool.random() ? 1 : -1); container.physicsBody?.linearDamping = 0.2
        let duration: CGFloat = 2.4
        let tumble3D = SKAction.customAction(withDuration: TimeInterval(duration)) { node, elapsed in
            let t = elapsed / CGFloat(duration)
            let spinY = t * .pi * 6.0; let xScale = cos(spinY)
            let spinX = t * .pi * 3.0; let yScale = 0.55 + 0.45 * abs(cos(spinX))
            front.xScale = xScale; front.yScale = yScale; topEdge.xScale = xScale
            let morphedColor = originalColor.blended(withFraction: t, of: nextLayerColor) ?? originalColor
            let morphedTop = (originalColor.blended(withFraction: 0.35, of: .white) ?? originalColor).blended(withFraction: t, of: nextTopColor) ?? nextTopColor
            let morphedSide = (originalColor.blended(withFraction: 0.35, of: .black) ?? originalColor).blended(withFraction: t, of: nextSideColor) ?? nextSideColor
            let isBackface = xScale < 0
            if isBackface {
                front.color = morphedColor.blended(withFraction: 0.35, of: .black) ?? morphedColor
                topEdge.isHidden = true; sideEdge.isHidden = false; sideEdge.color = morphedSide
            } else {
                front.color = morphedColor; topEdge.color = morphedTop; sideEdge.color = morphedSide
                topEdge.isHidden = false; sideEdge.isHidden = xScale < 0.4
            }
            let edgeOn = abs(xScale) < 0.25; topEdge.alpha = edgeOn ? 1.0 : 0.85; sideEdge.alpha = edgeOn ? 1.0 : 0.7
            shadow.xScale = 1.0 - t*0.5; shadow.alpha = 0.35 * (1.0 - t)
        }
        let fadeAndShrink = SKAction.group([
            SKAction.sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 1.0)]),
            SKAction.sequence([.wait(forDuration: 0.6), .scale(to: 0.35, duration: 1.8)])
        ])
        container.run(.sequence([.group([tumble3D, fadeAndShrink]), .removeFromParent()]))
    }
    func handleMiss(_ b: SKShapeNode) {
        playMissSound()
        parkBall(b)
        // Der er stadig bolde i spil -> ingen strafpoint
        if !activeBalls.isEmpty { updateHUD(); return }
        // Alle bolde er misset -> -5 point og alle bolde kommer ind igen
        score -= 5
        if score <= 0 {
            score = 0; isPlaying = false; isGameOver = true
            for x in allBalls { x.physicsBody?.velocity = .zero; x.isHidden = true }
            gameOverLabel.text = "GAME OVER"; gameOverLabel.fontColor = .red; gameOverLabel.isHidden = false
        } else {
            centerBalls()
            for x in allBalls { x.isHidden = false; launchBall(x) }
        }
        updateHUD()
    }
    func handleWallHit(wallName: String, ball: SKShapeNode) {
        guard let body = ball.physicsBody else { return }
        let speed = currentSpeed()
        var angle = atan2(body.velocity.dy, body.velocity.dx)
        if wallName == "leftWall" || wallName == "rightWall" { angle += CGFloat.random(in: -0.45...0.45) } else { angle += CGFloat.random(in: -0.35...0.35) }
        if abs(sin(angle)) < 0.35 { angle += sin(angle) >= 0 ? 0.35 : -0.35 }
        ball.physicsBody?.velocity = CGVector(dx: cos(angle)*speed, dy: sin(angle)*speed); playHitSound()
    }
    func didBegin(_ contact: SKPhysicsContact) {
        if !isPlaying { return }
        let a = contact.bodyA, b = contact.bodyB
        guard let ball = (a.categoryBitMask == PhysicsCategory.ball ? a.node : b.node) as? SKShapeNode else { return }
        if a.categoryBitMask == PhysicsCategory.wall || b.categoryBitMask == PhysicsCategory.wall {
            let wallNode = a.categoryBitMask == PhysicsCategory.wall ? a.node : b.node
            handleWallHit(wallName: wallNode?.name ?? "wall", ball: ball); return
        }
        if (a.categoryBitMask == PhysicsCategory.ball && b.categoryBitMask == PhysicsCategory.paddle) || (a.categoryBitMask == PhysicsCategory.paddle && b.categoryBitMask == PhysicsCategory.ball) {
            addPoints(1, at: ball.position)
            playHitSound(); armBall(ball); squash(ball)
            let speed = currentSpeed()
            let angle = CGFloat.random(in: 25.0...155.0) * .pi / 180
            var dx = cos(angle)*speed
            let hitPos = (ball.position.x - paddle.position.x) / (paddle.size.width/2); dx += hitPos * 120
            ball.physicsBody?.velocity = CGVector(dx: dx, dy: abs(sin(angle)*speed)); updateHUD(); return
        }
        if a.categoryBitMask == PhysicsCategory.brick || b.categoryBitMask == PhysicsCategory.brick {
            if !isArmed(ball) { return }
            let brick = a.categoryBitMask == PhysicsCategory.brick ? a.node : b.node
            if let brick = brick {
                // --- NYT: Retnings-regel ---
                // Bold nedefra -> brick falder ned
                // Bold oppefra på øverste lag -> brick må IKKE falde, bouncer som væg
                let allBrickYs = children.compactMap { $0.name == "brick" ? $0.position.y : nil }
                let topY = allBrickYs.max() ?? brick.position.y
                let isTopmostRow = abs(brick.position.y - topY) < 1.0
                let dyContact = contact.contactPoint.y - brick.position.y
                let vel = ball.physicsBody?.velocity ?? .zero
                let hitFromBelow = dyContact < -2 || (ball.position.y < brick.position.y && vel.dy > 0)
                let hitFromAbove = dyContact > 2 || (ball.position.y > brick.position.y && vel.dy < 0)
                // 1) Øverste lag ramt oppefra -> ALDRIG fald, kun bounce
                if isTopmostRow && hitFromAbove && !hitFromBelow {
                    playHitSound()
                    let speed = currentSpeed()
                    if vel.dy < 0 {
                        let angle = CGFloat.random(in: 35...145) * .pi / 180
                        ball.physicsBody?.velocity = CGVector(dx: cos(angle)*speed, dy: abs(sin(angle)*speed))
                    }
                    return
                }
                // 2) Generel regel: Kun hit nedefra får brick til at falde
                if !hitFromBelow {
                    playHitSound()
                    return
                }
                // 3) Hit nedefra -> falder som før
                addPoints(2, at: brick.position)
                makeBrickFall(brick)
                playHitSound(); disarmBall(ball); updateHUD()
                let remaining = children.filter({ $0.name == "brick" }).count
                if remaining == 0 {
                    if hiddenRowsRemaining > 0 {
                        let nextBatch = min(hiddenRowsRemaining, maxVisibleRows)
                        hiddenRowsRemaining -= nextBatch
                        gameOverLabel.text = "NEXT WAVE!"; gameOverLabel.fontColor = .orange; gameOverLabel.isHidden = false
                        DispatchQueue.main.asyncAfter(deadline: .now()+0.8) {
                            self.createBricks(rows: nextBatch)
                            self.centerBalls()
                            for b in self.allBalls { b.isHidden = false; self.launchBall(b) }
                            self.isPlaying = true; self.gameOverLabel.isHidden = true; self.updateHUD()
                        }
                    } else {
                        isPlaying = false
                        for b in allBalls { b.physicsBody?.velocity = .zero }
                        let nextBalls = ballCount(for: level + 1)
                        gameOverLabel.text = "LEVEL \(level) CLEAR! NEXT: \(ballsText(nextBalls))!"
                        gameOverLabel.fontColor = .green; gameOverLabel.isHidden = false
                        DispatchQueue.main.asyncAfter(deadline: .now()+1.5) {
                            self.setupLevel(self.level + 1)
                            self.centerBalls()
                            for b in self.allBalls { b.isHidden = false }
                            self.launchAllBalls(atSpeed: self.getStartSpeed()); self.isPlaying = true; self.gameOverLabel.isHidden = true; self.updateHUD()
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
            if n.name == "speakerButton" || n.parent?.name == "speakerButton" || n.name == "speakerIcon" || n.parent?.name == "speakerIcon" { toggleSound(); return }
            if n.name == "resetButton" || n.parent?.name == "resetButton" { confirmResetAll(); return }
            if n.name == "levelBox" || n === levelLabel || n.parent === levelBox { promptForLevel(); return }
            if n.name == "speedBox" || n === speedLabel || n.parent === speedBox { promptForSpeed(); return }
        }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 49 { handleStatusToggle() } }
    override func update(_ currentTime: TimeInterval) {
        if !isPlaying { return }
        if let view = self.view, let window = view.window {
            let mW = window.mouseLocationOutsideOfEventStream
            let mV = view.convert(mW, from: nil)
            // Pladen må aldrig komme uden for skærmen – hverken til højre eller venstre
            let half = paddle.size.width / 2
            let mouseX = convertPoint(fromView: mV).x
            paddle.position.x = min(max(mouseX, half), size.width - half)
        }
        for b in activeBalls {
            updateBallShape(b)
            if b.position.y < 20 {
                handleMiss(b)
                if isGameOver { break }
            }
        }
        if startTime == 0 { startTime = currentTime }
        let elapsed = currentTime - startTime
        timeLabel.text = String(format: "%02d:%05.2f", Int(elapsed)/60, elapsed.truncatingRemainder(dividingBy: 60))
    }
}
