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
    var highScore = 0
    var playerName = ""
    var playerBox: SKShapeNode!
    var playerLabel: SKLabelNode!
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
    func pointMultiplier() -> Int { (ballCount(for: level) == 3 && activeBalls.count >= 3) ? 3 : 1 }
    /// Lægger point til (ganget med multiplier) og viser "+N" der hvor det skete
    func addPoints(_ base: Int, at pos: CGPoint) {
        let m = pointMultiplier()
        let pts = base * m
        score += pts
        if score > highScore { highScore = score; saveHighScore() }
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
        
        loadPlayer()
        installMouseMonitor()
        setupHUD()
        layoutHUD()
        prepareGame()
        if playerName.isEmpty { promptForPlayer(firstTime: true) }
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
        // Ekstra-bolde fra sammenstød gælder kun det level, de kom i
        for b in extraBalls where isBonusBall(b) { b.removeFromParent() }
        extraBalls.removeAll { isBonusBall($0) }
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
        // En parkeret (misset) bold må ikke kunne ramme noget
        b.physicsBody?.categoryBitMask = 0
        b.physicsBody?.collisionBitMask = 0
        b.physicsBody?.contactTestBitMask = 0
        b.isHidden = true
        b.position = CGPoint(x: size.width/2, y: size.height/2)
    }
    func pauseBalls() {
        showCursorNow()
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
        statusButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 96, height: 40), cornerRadius: 10)
        statusButton.fillColor = .systemGreen; statusButton.strokeColor = .white
        statusButton.name = "statusButton"; addChild(statusButton)
        statusButtonLabel = SKLabelNode(fontNamed: "Menlo-Bold"); statusButtonLabel.fontSize = 13
        statusButtonLabel.fontColor = .black; statusButtonLabel.position = CGPoint(x: 48, y: 13)
        statusButton.addChild(statusButtonLabel)
        
        speakerButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 62, height: 40), cornerRadius: 10)
        speakerButton.fillColor = SKColor(white: 0.25, alpha: 0.9); speakerButton.strokeColor = .white
        speakerButton.name = "speakerButton"; addChild(speakerButton)
        speakerLabel = SKLabelNode(fontNamed: "Menlo-Bold"); speakerLabel.fontSize = 13
        speakerLabel.isHidden = true; speakerButton.addChild(speakerLabel)
        
        // SF Symbols speaker icons - typical 🔊 and 🔇 with X
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 19, weight: .bold, scale: .medium)
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
        speakerIcon = SKSpriteNode(texture: initialTex, color: .white, size: CGSize(width: 26, height: 26))
        speakerIcon.colorBlendFactor = 1.0
        speakerIcon.position = CGPoint(x: 31, y: 20)
        speakerIcon.name = "speakerIcon"
        speakerButton.addChild(speakerIcon)
        
        levelBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 112, height: 40), cornerRadius: 10)
        levelBox.fillColor = SKColor(white: 0.2, alpha: 0.9); levelBox.strokeColor = .systemPurple
        levelBox.name = "levelBox"; addChild(levelBox)
        levelLabel = SKLabelNode(fontNamed: "Menlo-Bold"); levelLabel.fontSize = 13; levelLabel.fontColor = .systemPurple
        levelLabel.position = CGPoint(x: 56, y: 13); levelBox.addChild(levelLabel)
        
        highBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 118, height: 40), cornerRadius: 10)
        highBox.fillColor = SKColor(white: 0.2, alpha: 0.9); highBox.strokeColor = .white
        highBox.name = "highBox"; addChild(highBox)
        highScoreLabel = SKLabelNode(fontNamed: "Menlo-Bold"); highScoreLabel.fontSize = 13; highScoreLabel.fontColor = .cyan
        highScoreLabel.position = CGPoint(x: 59, y: 13); highBox.addChild(highScoreLabel)
        
        speedBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 128, height: 40), cornerRadius: 10)
        speedBox.fillColor = SKColor(white: 0.2, alpha: 0.9); speedBox.strokeColor = .yellow
        speedBox.name = "speedBox"; addChild(speedBox)
        speedLabel = SKLabelNode(fontNamed: "Menlo-Bold"); speedLabel.fontSize = 13; speedLabel.fontColor = .yellow
        speedLabel.position = CGPoint(x: 64, y: 13); speedBox.addChild(speedLabel)
        
        resetButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 118, height: 40), cornerRadius: 10)
        resetButton.fillColor = SKColor(white: 0.25, alpha: 0.9); resetButton.strokeColor = .systemRed
        resetButton.name = "resetButton"; addChild(resetButton)
        resetButtonLabel = SKLabelNode(fontNamed: "Menlo-Bold"); resetButtonLabel.fontSize = 13; resetButtonLabel.fontColor = .systemRed
        resetButtonLabel.text = "RESET ALL"; resetButtonLabel.position = CGPoint(x: 59, y: 13); resetButton.addChild(resetButtonLabel)
        
        timeBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 108, height: 40), cornerRadius: 10)
        timeBox.fillColor = SKColor(white: 0.2, alpha: 0.9); timeBox.strokeColor = .white
        addChild(timeBox)
        timeLabel = SKLabelNode(fontNamed: "Menlo-Bold"); timeLabel.fontSize = 13
        timeLabel.position = CGPoint(x: 54, y: 13); timeBox.addChild(timeLabel)
        
        scoreBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 124, height: 40), cornerRadius: 10)
        scoreBox.fillColor = SKColor(white: 0.2, alpha: 0.9); scoreBox.strokeColor = .white
        addChild(scoreBox)
        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold"); scoreLabel.fontSize = 13; scoreLabel.fontColor = .systemYellow
        scoreLabel.position = CGPoint(x: 62, y: 13); scoreBox.addChild(scoreLabel)
        
        playerBox = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 150, height: 40), cornerRadius: 10)
        playerBox.fillColor = SKColor(white: 0.2, alpha: 0.9); playerBox.strokeColor = .systemGreen
        playerBox.name = "playerBox"; addChild(playerBox)
        playerLabel = SKLabelNode(fontNamed: "Menlo-Bold"); playerLabel.fontSize = 13; playerLabel.fontColor = .systemGreen
        playerLabel.position = CGPoint(x: 75, y: 13); playerBox.addChild(playerLabel)

        gameOverLabel = SKLabelNode(fontNamed: "Menlo-Bold"); gameOverLabel.fontSize = 24
        addChild(gameOverLabel)
    }
    
    func layoutHUD() {
        guard statusButton != nil else { return }
        // Felterne i toppen lægges efter hinanden ud fra deres bredde,
        // og skaleres ned hvis vinduet er for smalt, så de aldrig overlapper.
        let left: [SKShapeNode] = [statusButton, speakerButton, playerBox, levelBox, highBox, speedBox]
        let right: [SKShapeNode] = [resetButton, timeBox, scoreBox]
        let gap: CGFloat = 8, margin: CGFloat = 12, minMiddle: CGFloat = 20
        let wl = left.map { $0.path?.boundingBox.width ?? 0 }
        let wr = right.map { $0.path?.boundingBox.width ?? 0 }
        let needed = wl.reduce(0, +) + wr.reduce(0, +) + gap * CGFloat(left.count + right.count - 2) + margin * 2 + minMiddle
        let k = min(1, size.width / needed)
        let y = size.height - 12 - 40 * k
        var x = margin
        for (n, w) in zip(left, wl) { n.setScale(k); n.position = CGPoint(x: x, y: y); x += (w + gap) * k }
        x = size.width - margin
        for (n, w) in zip(right.reversed(), wr.reversed()) { n.setScale(k); x -= w * k; n.position = CGPoint(x: x, y: y); x -= gap * k }
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
        b.physicsBody?.categoryBitMask = PhysicsCategory.ball
        b.physicsBody?.collisionBitMask = PhysicsCategory.paddle | PhysicsCategory.wall | PhysicsCategory.ball
        b.physicsBody?.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.wall | PhysicsCategory.ball
        setBallColor(b, .systemGray)
    }
    func armBall(_ b: SKShapeNode) {
        if b.userData == nil { b.userData = NSMutableDictionary() }
        b.userData?["armed"] = true
        b.physicsBody?.categoryBitMask = PhysicsCategory.ball
        b.physicsBody?.collisionBitMask = PhysicsCategory.paddle | PhysicsCategory.wall | PhysicsCategory.brick | PhysicsCategory.ball
        b.physicsBody?.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.brick | PhysicsCategory.wall | PhysicsCategory.ball
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
        let shownName = playerName.isEmpty ? "?" : (playerName.count > 11 ? String(playerName.prefix(10)) + "…" : playerName)
        playerLabel.text = "👤 \(shownName)"
        // Faktisk fart (i %, 100% = 125) – opdateres også løbende i update()
        if !isPlaying { speedLabel.text = "Speed: \(Int((currentSpeed() / baseSpeed * 100).rounded()))%" }
        speakerIcon?.texture = soundOn ? speakerOnTexture : speakerOffTexture
        if let icon = speakerIcon {
            icon.color = soundOn ? .white : .systemRed
            icon.colorBlendFactor = 1.0
        }
        let ballsTag = allBalls.count > 1 ? " " + String(repeating: "●", count: allBalls.count) : ""
        if hiddenRowsRemaining > 0 { levelLabel.text = "Level: \(level) (+\(hiddenRowsRemaining))\(ballsTag)" }
        else { levelLabel.text = "Level: \(level)\(ballsTag)" }
        levelLabel.fontSize = (levelLabel.text?.count ?? 0) > 13 ? 11 : 13
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
                isPlaying = true; gameOverLabel.isHidden = true; launchAllBalls(atSpeed: currentSpeed())
            }
        }
        updateHUD()
    }
    func toggleSound() { soundOn.toggle(); UserDefaults.standard.set(soundOn, forKey: "SoundOn"); updateHUD(); if soundOn { playHitSound() } }
    func restartGame() { score = 25; prepareGame() }
    
    func promptForLevel() {
        if isPlaying { gamePaused = true; isPlaying = false; pauseBalls() }
        DispatchQueue.main.async {
            let tf = NSTextField(string: "\(self.level)")
            let okPressed = InputDialog.run(title: "Change Level", message: "Enter level number (1-99):", field: tf)
            if okPressed, let nl = Int(tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), (1...99).contains(nl) {
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
            let nowPct = Int((self.currentSpeed() / self.baseSpeed * 100).rounded())
            let tf = NSTextField(string: "\(nowPct)")
            let okPressed = InputDialog.run(title: "Change Speed",
                                            message: "Enter ball speed in % (50-300).\nThe ball gets this speed right away, and it still goes up as you score points.",
                                            field: tf)
            if okPressed {
                // Tillad "150", "150%" og " 150 " – og hold værdien inden for 50-300
                let raw = tf.stringValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let typed = Int(raw) {
                    let wanted = CGFloat(min(max(typed, 50), 300))
                    // Det du skriver er den fart bolden får NU (og det der står i Speed-feltet).
                    // Derfor regnes level- og point-tillæg fra, når start-farten gemmes.
                    let factor = self.currentSpeed() / max(self.getStartSpeed(), 0.001)
                    let ns = max(10, Int((wanted / factor).rounded()))
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
            alert.messageText = "Reset All Progress?"; alert.informativeText = "This will reset score, level, speed and the high score for the current player. Other players keep their high scores. This cannot be undone."
            alert.alertStyle = .warning; alert.addButton(withTitle: "Reset All"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { self.resetAllProgress() }
            else if self.gamePaused { self.gamePaused = false; self.isPlaying = true; self.resumeBalls(); self.gameOverLabel.isHidden = true; self.updateHUD() }
        }
    }
    // MARK: - Spillere og high scores
    // High scores gemmes pr. spiller i UserDefaults under "PlayerHighScores" [navn: point]
    func allHighScores() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: "PlayerHighScores") as? [String: Int]) ?? [:]
    }
    func saveHighScore() {
        guard !playerName.isEmpty else { return }
        var all = allHighScores()
        if highScore > (all[playerName] ?? 0) || highScore == 0 { all[playerName] = highScore }
        UserDefaults.standard.set(all, forKey: "PlayerHighScores")
    }
    func selectPlayer(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        playerName = String(clean.prefix(16))
        UserDefaults.standard.set(playerName, forKey: "CurrentPlayer")
        var all = allHighScores()
        if all[playerName] == nil { all[playerName] = 0; UserDefaults.standard.set(all, forKey: "PlayerHighScores") }
        highScore = all[playerName] ?? 0
        updateHUD()
    }
    func loadPlayer() {
        var all = allHighScores()
        // Flyt gammel fælles high score over til første spiller
        let old = UserDefaults.standard.integer(forKey: "HighScore")
        playerName = UserDefaults.standard.string(forKey: "CurrentPlayer") ?? ""
        if !playerName.isEmpty {
            if old > 0 && all.isEmpty { all[playerName] = old; UserDefaults.standard.set(all, forKey: "PlayerHighScores") }
            highScore = all[playerName] ?? 0
        } else {
            highScore = old
        }
    }
    /// Spørg hvem der spiller – vælg en eksisterende spiller eller skriv et nyt navn
    func promptForPlayer(firstTime: Bool = false) {
        if isPlaying { gamePaused = true; isPlaying = false; pauseBalls() }
        DispatchQueue.main.async {
            let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
            let names = self.allHighScores().keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            combo.addItems(withObjectValues: names)
            combo.completes = true
            combo.stringValue = self.playerName
            let okPressed = InputDialog.run(title: firstTime ? "Welcome to Roman's Breakout!" : "Who is playing?",
                                            message: "Choose a player from the list or type a new name:",
                                            field: combo, showCancel: !firstTime)
            if okPressed {
                let typed = combo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !typed.isEmpty {
                    if typed != self.playerName { self.selectPlayer(typed); self.score = 25; self.prepareGame() }
                } else if self.playerName.isEmpty {
                    self.selectPlayer("Player 1")
                }
            }
            if self.gamePaused { self.gamePaused = false; self.isPlaying = true; self.resumeBalls(); self.gameOverLabel.isHidden = true }
            self.updateHUD()
        }
    }
    /// Viser alle spilleres high scores, bedste først
    func showHighScores() {
        if isPlaying { gamePaused = true; isPlaying = false; pauseBalls() }
        DispatchQueue.main.async {
            self.saveHighScore()
            let list = self.allHighScores().sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            let medals = ["🥇", "🥈", "🥉"]
            var text = ""
            for (i, e) in list.enumerated() {
                let mark = i < 3 ? medals[i] : "  \(i + 1)."
                let me = e.key == self.playerName ? "  ← playing" : ""
                text += "\(mark)  \(e.key):  \(e.value)\(me)\n"
            }
            if text.isEmpty { text = "No high scores yet." }
            let alert = NSAlert()
            alert.messageText = "High Scores"
            alert.informativeText = text
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            if self.gamePaused { self.gamePaused = false; self.isPlaying = true; self.resumeBalls(); self.gameOverLabel.isHidden = true; self.updateHUD() }
        }
    }

    func resetAllProgress() {
        score = 25; highScore = 0; level = 1; startSpeedPercent = 100
        // Nulstiller kun den nuværende spillers high score – de andre spillere beholder deres
        if !playerName.isEmpty {
            var all = allHighScores(); all[playerName] = 0
            UserDefaults.standard.set(all, forKey: "PlayerHighScores")
        }
        UserDefaults.standard.removeObject(forKey: "HighScore")
        UserDefaults.standard.set(1, forKey: "CurrentLevel"); UserDefaults.standard.set(100, forKey: "StartSpeedPercent")
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
        if isBonusBall(b) {
            // Ekstra-bolde forsvinder bare, når de misses
            b.removeFromParent()
            extraBalls.removeAll { $0 === b }
            if !activeBalls.isEmpty { updateHUD(); return }
        } else {
            parkBall(b)
        }
        // Der er stadig bolde i spil -> ingen strafpoint
        if !activeBalls.isEmpty { updateHUD(); return }
        // Alle bolde er misset -> -5 point og alle bolde kommer ind igen
        score -= 5
        if score <= 0 {
            score = 0; isPlaying = false; isGameOver = true
            showCursorNow()
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
    // MARK: - Bolde der rammer hinanden
    // Når 2 eller 3 bolde støder sammen: stor eksplosion, en ekstra bold og +100 point
    var lastBallCollision: TimeInterval = 0
    func isBonusBall(_ b: SKNode) -> Bool { (b.userData?["bonus"] as? Bool) ?? false }
    func handleBallsCollided(at point: CGPoint, color: SKColor) {
        guard isPlaying else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastBallCollision > 1.0 else { return }     // ikke flere gange for samme sammenstød
        lastBallCollision = now
        // Stor eksplosion – flere farver
        explode(at: point, color: color)
        explode(at: point, color: .systemOrange)
        explode(at: point, color: .white)
        if soundOn { NSSound(named: "Glass")?.play() }
        // +100 point (fast bonus)
        score += 100
        if score > highScore { highScore = score; saveHighScore() }
        // Ekstra bold sendes ud fra stedet
        let extra = SKShapeNode(circleOfRadius: 20)
        configureBallPhysics(extra)
        if extra.userData == nil { extra.userData = NSMutableDictionary() }
        extra.userData?["bonus"] = true
        extra.position = CGPoint(x: min(max(point.x, 40), size.width - 40), y: min(max(point.y, 120), size.height - 160))
        addChild(extra)
        extraBalls.append(extra)
        launchBall(extra)
        // Ballon med besked – forsvinder efter 3 sekunder, spillet kører videre
        showBalloon("EXTRA 100 POINT!", at: point)
        updateHUD()
    }
    func showBalloon(_ text: String, at point: CGPoint) {
        let balloon = SKNode()
        balloon.zPosition = 40
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text; label.fontSize = 20; label.fontColor = .white
        label.verticalAlignmentMode = .center
        let w = label.frame.width + 40, h: CGFloat = 54
        let body = SKShapeNode(ellipseOf: CGSize(width: w, height: h))
        body.fillColor = .systemPink; body.strokeColor = .white; body.lineWidth = 3; body.glowWidth = 3
        // lille "knude" og snor under ballonen
        let knot = SKShapeNode(path: { let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: -6, y: -h/2 - 8), CGPoint(x: 6, y: -h/2 - 8), CGPoint(x: 0, y: -h/2 + 1)]); p.closeSubpath(); return p }())
        knot.fillColor = .systemPink; knot.strokeColor = .white; knot.lineWidth = 1.5
        let string = SKShapeNode(path: { let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: -h/2 - 8))
            p.addCurve(to: CGPoint(x: 0, y: -h/2 - 60), control1: CGPoint(x: 14, y: -h/2 - 25), control2: CGPoint(x: -14, y: -h/2 - 42))
            return p }())
        string.strokeColor = .white; string.lineWidth = 1.5
        let shine = SKShapeNode(ellipseOf: CGSize(width: w * 0.25, height: 10))
        shine.fillColor = SKColor(white: 1, alpha: 0.45); shine.strokeColor = .clear
        shine.position = CGPoint(x: -w * 0.22, y: h * 0.2)
        balloon.addChild(string); balloon.addChild(body); balloon.addChild(knot); balloon.addChild(shine); balloon.addChild(label)
        let x = min(max(point.x, w/2 + 10), size.width - w/2 - 10)
        balloon.position = CGPoint(x: x, y: min(point.y + 40, size.height - 140))
        balloon.setScale(0.2)
        addChild(balloon)
        let pop = SKAction.scale(to: 1.0, duration: 0.25); pop.timingMode = .easeOut
        let floatUp = SKAction.moveBy(x: 0, y: 40, duration: 3.0)
        let wobble = SKAction.repeatForever(.sequence([.rotate(toAngle: 0.06, duration: 0.4), .rotate(toAngle: -0.06, duration: 0.4)]))
        balloon.run(wobble)
        balloon.run(.sequence([pop, .group([floatUp, .sequence([.wait(forDuration: 2.5), .fadeOut(withDuration: 0.5)])]), .removeFromParent()]))
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if !isPlaying { return }
        let a = contact.bodyA, b = contact.bodyB
        if a.categoryBitMask == PhysicsCategory.ball && b.categoryBitMask == PhysicsCategory.ball {
            if let n1 = a.node as? SKShapeNode, let n2 = b.node as? SKShapeNode, !n1.isHidden, !n2.isHidden {
                let point = contact.contactPoint
                DispatchQueue.main.async { self.handleBallsCollided(at: point, color: self.skin(n1)?.fillColor ?? .systemYellow) }
            }
            return
        }
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
                            self.launchAllBalls(atSpeed: self.currentSpeed()); self.isPlaying = true; self.gameOverLabel.isHidden = true; self.updateHUD()
                        }
                    }
                }
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        // Klik mens man spiller (musen er låst) skal ikke gøre noget – pladen kører bare videre
        if pointerLocked && isPlaying { return }
        let loc = event.location(in: self)
        let nodes = nodes(at: loc)
        for n in nodes {
            if n.name == "statusButton" || n.parent?.name == "statusButton" { handleStatusToggle(); return }
            if n.name == "speakerButton" || n.parent?.name == "speakerButton" || n.name == "speakerIcon" || n.parent?.name == "speakerIcon" { toggleSound(); return }
            if n.name == "resetButton" || n.parent?.name == "resetButton" { confirmResetAll(); return }
            if n.name == "playerBox" || n === playerLabel || n.parent === playerBox { promptForPlayer(); return }
            if n.name == "highBox" || n === highScoreLabel || n.parent === highBox { showHighScores(); return }
            if n.name == "levelBox" || n === levelLabel || n.parent === levelBox { promptForLevel(); return }
            if n.name == "speedBox" || n === speedLabel || n.parent === speedBox { promptForSpeed(); return }
        }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 49 { handleStatusToggle() } }
    // MARK: - Musepil
    // Musepilen skjules mens man spiller og musen er over spillet.
    // Den vises igen ved pause, game over, dialoger, eller når musen er uden for vinduet.
    var cursorHidden = false
    // Mens man spiller, "låses" musen til spillet: pilen er skjult og kan ikke forlade vinduet,
    // så man ikke ved et uheld rammer andre vinduer, Stage Manager, hjørner eller lukker spillet.
    // Pladen styres så af musens bevægelse (delta) i stedet for dens position.
    var pointerLocked = false
    func updateCursor() {
        var shouldLock = false
        if isPlaying, NSApp.isActive, let view = self.view, let window = view.window, window.isKeyWindow {
            if pointerLocked {
                shouldLock = true
            } else {
                let p = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                shouldLock = view.bounds.contains(p)
            }
        }
        if shouldLock && !pointerLocked { lockPointer() }
        else if !shouldLock && pointerLocked { unlockPointer() }
    }
    func lockPointer() {
        if !cursorHidden { NSCursor.hide(); cursorHidden = true }
        CGAssociateMouseAndMouseCursorPosition(0)
        pointerLocked = true
    }
    func unlockPointer() {
        guard pointerLocked else { return }
        pointerLocked = false
        CGAssociateMouseAndMouseCursorPosition(1)
        // Sæt musepilen der hvor pladen er, så den ikke "hopper"
        if let view = self.view, let window = view.window, let screen = window.screen ?? NSScreen.screens.first {
            let inView = convertPoint(toView: paddle.position)
            let inWindow = view.convert(inView, to: nil)
            let onScreen = window.convertPoint(toScreen: inWindow)
            let mainH = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: mainH - onScreen.y))
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
    }
    func showCursorNow() { unlockPointer(); if cursorHidden { NSCursor.unhide(); cursorHidden = false } }
    override func willMove(from view: SKView) {
        showCursorNow()
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        super.willMove(from: view)
    }
    func movePaddle(by dx: CGFloat) {
        let half = paddle.size.width / 2
        paddle.position.x = min(max(paddle.position.x + dx, half), size.width - half)
    }
    // Fanger ALLE musebevægelser – også mens en museknap holdes nede (klik/træk),
    // så pladen aldrig stopper fordi man klikker.
    var mouseMonitor: Any?
    func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, self.pointerLocked, self.isPlaying { self.movePaddle(by: event.deltaX) }
            }
            return event
        }
    }

    override func update(_ currentTime: TimeInterval) {
        updateCursor()
        if !isPlaying { return }
        if !pointerLocked, let view = self.view, let window = view.window {
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
        // Speed-feltet opdateres løbende med boldens faktiske fart lige nu
        let liveSpeed = activeBalls.compactMap { $0.physicsBody?.velocity }.map { hypot($0.dx, $0.dy) }.max() ?? 0
        let livePct = Int((liveSpeed / baseSpeed * 100).rounded())
        let speedText = "Speed: \(livePct)%"
        if speedLabel.text != speedText { speedLabel.text = speedText }
    }
}


// MARK: - Indtastnings-vindue
// Et rigtigt vindue (ikke NSAlert), så tekstfeltet altid får tastatur-fokus.
// På macOS 26 kunne NSAlert-vinduet ikke blive "key", så man kunne ikke skrive i feltet.
final class InputDialog: NSObject {
    private var window: NSWindow!
    @objc private func okPressed(_ sender: Any?) { NSApp.stopModal(withCode: .OK) }
    @objc private func cancelPressed(_ sender: Any?) { NSApp.stopModal(withCode: .cancel) }

    /// Viser dialogen og returnerer true hvis der blev trykket OK (eller Enter)
    static func run(title: String, message: String, field: NSTextField, showCancel: Bool = true) -> Bool {
        let d = InputDialog()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 170),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.level = .modalPanel
        d.window = w
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 170))

        let label = NSTextField(wrappingLabelWithString: message)
        label.frame = NSRect(x: 20, y: 90, width: 340, height: 60)
        label.font = NSFont.systemFont(ofSize: 13)
        content.addSubview(label)

        field.frame = NSRect(x: 20, y: 58, width: 340, height: 26)
        field.font = NSFont.systemFont(ofSize: 15)
        content.addSubview(field)

        let ok = NSButton(title: "OK", target: d, action: #selector(okPressed(_:)))
        ok.frame = NSRect(x: 270, y: 14, width: 90, height: 32)
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        content.addSubview(ok)
        if showCancel {
            let cancel = NSButton(title: "Cancel", target: d, action: #selector(cancelPressed(_:)))
            cancel.frame = NSRect(x: 172, y: 14, width: 90, height: 32)
            cancel.bezelStyle = .rounded
            cancel.keyEquivalent = "\u{1b}"
            content.addSubview(cancel)
        }
        w.contentView = content
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(field)
        field.selectText(nil)
        let result = NSApp.runModal(for: w)
        w.orderOut(nil)
        return result == .OK
    }
}
