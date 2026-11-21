import SpriteKit
import AppKit

// MARK: - Power-ups
// Når en klods går i stykker, er der 25% chance for, at den taber en kapsel.
// Fang kapslen med pladen for at få dens power-up:
//   W  WIDE   – pladen bliver 50% bredere i 15 sek.
//   S  SLOW   – boldene kører 40% langsommere i 10 sek. (dog aldrig under 150% fart)
//   L  LASER  – pladen skyder automatisk laserskud i 10 sek.
//   +  SHIELD – et skjold i bunden redder én bold
// Fanger man den samme igen, mens den er aktiv, starter tiden forfra.
// Alle power-ups forsvinder ved nyt spil. Kapsler og skud i luften forsvinder ved baneskift.

enum PowerUpKind: Int, CaseIterable {
    case wide, slow, laser, shield

    var letter: String {
        switch self {
        case .wide: return "W"
        case .slow: return "S"
        case .laser: return "L"
        case .shield: return "+"
        }
    }
    var title: String {
        switch self {
        case .wide: return "WIDE PADDLE"
        case .slow: return "SLOW BALL"
        case .laser: return "LASER"
        case .shield: return "SHIELD"
        }
    }
    var color: SKColor {
        switch self {
        case .wide: return .systemBlue
        case .slow: return .systemTeal
        case .laser: return .systemRed
        case .shield: return .systemGreen
        }
    }
    /// Varighed i sekunder (skjoldet varer til det bliver ramt)
    var duration: TimeInterval {
        switch self {
        case .wide: return 15
        case .slow: return 10
        case .laser: return 10
        case .shield: return 0
        }
    }
}

extension GameScene {
    // Indstillinger
    var dropChance: Double { 0.25 }           // chance for kapsel pr. knust klods
    var maxFallingCapsules: Int { 3 }
    var capsuleFallSpeed: CGFloat { 170 }
    var laserInterval: TimeInterval { 0.45 }  // tid mellem laserskud
    var laserSpeed: CGFloat { 650 }
    var shieldY: CGFloat { 40 }

    var paddleWidthFactor: CGFloat { wideRemaining > 0 ? 1.5 : 1 }
    var slowFactor: CGFloat { slowRemaining > 0 ? 0.6 : 1 }

    // MARK: Kapsler
    /// Kaldes når en klods går i stykker – giver af og til en kapsel
    func maybeDropPowerUp(at pos: CGPoint) {
        guard isPlaying, capsules.count < maxFallingCapsules, Double.random(in: 0..<1) < dropChance,
              let kind = PowerUpKind.allCases.randomElement() else { return }
        spawnCapsule(kind, at: pos)
    }

    func spawnCapsule(_ kind: PowerUpKind, at pos: CGPoint) {
        let cap = SKShapeNode(rect: CGRect(x: -26, y: -11, width: 52, height: 22), cornerRadius: 11)
        cap.fillColor = kind.color
        cap.strokeColor = .white; cap.lineWidth = 2; cap.glowWidth = 3
        cap.zPosition = 15
        let shine = SKShapeNode(rect: CGRect(x: -20, y: 2, width: 40, height: 5), cornerRadius: 2.5)
        shine.fillColor = SKColor(white: 1, alpha: 0.4); shine.strokeColor = .clear
        cap.addChild(shine)
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = kind.letter; label.fontSize = 15; label.fontColor = .white
        label.verticalAlignmentMode = .center; label.zPosition = 1
        cap.addChild(label)
        cap.userData = NSMutableDictionary(dictionary: ["kind": kind.rawValue])
        cap.position = pos
        addChild(cap)
        capsules.append(cap)
        // pulserer let, så den er nem at se
        cap.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.3), .scale(to: 1.0, duration: 0.3)])))
    }

    // MARK: Opdatering hvert billede (kun mens der spilles)
    func updatePowerUps(_ dt: TimeInterval) {
        let step = CGFloat(dt)

        // Kapsler falder – fanges hvis de rammer pladen
        for cap in capsules {
            cap.position.y -= capsuleFallSpeed * step
            let caught = abs(cap.position.x - paddle.position.x) < paddleHalfWidth + 26
                      && abs(cap.position.y - paddle.position.y) < 22
            if caught {
                let raw = (cap.userData?["kind"] as? Int) ?? 0
                let kind = PowerUpKind(rawValue: raw) ?? .wide
                cap.removeFromParent()
                activatePowerUp(kind, at: cap.position)
            } else if cap.position.y < -20 {
                cap.removeFromParent()
            }
        }
        capsules.removeAll { $0.parent == nil }

        // Tid der løber ud
        if wideRemaining > 0 {
            wideRemaining -= dt
            if wideRemaining <= 0 { wideRemaining = 0; refreshPaddleShape() }
        }
        if slowRemaining > 0 {
            slowRemaining -= dt
            if slowRemaining <= 0 { slowRemaining = 0; applyNewSpeedToBalls() }
        }
        if laserRemaining > 0 {
            laserRemaining -= dt
            if laserRemaining <= 0 {
                laserRemaining = 0
                removeLaserCannons()
            } else {
                positionLaserCannons()
                laserCooldown -= dt
                if laserCooldown <= 0 { fireLasers(); laserCooldown = laserInterval }
            }
        }
        updateLasers(step)
        updatePowerUpLabel()
    }

    func activatePowerUp(_ kind: PowerUpKind, at pos: CGPoint) {
        if soundOn { NSSound(named: "Hero")?.play() }
        floatingText("\(kind.title)!", at: CGPoint(x: pos.x, y: paddle.position.y + 60), color: kind.color)
        score += 5
        if score > highScore { highScore = score; saveHighScore() }
        switch kind {
        case .wide:
            let wasActive = wideRemaining > 0
            wideRemaining = kind.duration
            if !wasActive { refreshPaddleShape() }
        case .slow:
            let wasActive = slowRemaining > 0
            slowRemaining = kind.duration
            if !wasActive { applyNewSpeedToBalls() }
        case .laser:
            laserRemaining = kind.duration
            laserCooldown = 0
            addLaserCannons()
        case .shield:
            shieldActive = true
            createShield()
        }
        updatePowerUpLabel()
        updateHUD()
    }

    // MARK: Pladens form (WIDE)
    /// Almindelig metalplade i den bredde, der passer (bredere med WIDE)
    func applyNormalPaddleShape() {
        let newSize = CGSize(width: 120 * paddleWidthFactor, height: 20)
        paddle.size = newSize
        paddle.texture = bevelTexture(size: newSize, color: paddleMetalColor, radius: 10)
        (paddle.childNode(withName: "paddleShadow") as? SKSpriteNode)?.size = newSize
        setPaddleBody(SKPhysicsBody(rectangleOf: newSize))
        clampPaddle()
    }
    /// Opdaterer pladen efter WIDE starter/slutter – både den normale og den elastiske ovale
    func refreshPaddleShape() {
        if elasticRemaining > 0 && paddle.childNode(withName: "oval") != nil {
            buildOvalNodes(popIn: false)
            clampPaddle()
        } else {
            applyNormalPaddleShape()
        }
        positionLaserCannons()
    }
    func clampPaddle() {
        let half = paddleHalfWidth
        paddle.position.x = min(max(paddle.position.x, half), size.width - half)
    }

    // MARK: Laser
    func addLaserCannons() {
        guard paddle.childNode(withName: "cannon") == nil else { return }
        for _ in 0..<2 {
            let cannon = SKSpriteNode(color: .systemRed, size: CGSize(width: 8, height: 14))
            cannon.name = "cannon"; cannon.zPosition = 2
            let tip = SKSpriteNode(color: .white, size: CGSize(width: 4, height: 4))
            tip.position = CGPoint(x: 0, y: 7)
            cannon.addChild(tip)
            paddle.addChild(cannon)
        }
        positionLaserCannons()
    }
    func positionLaserCannons() {
        let cannons = paddle.children.filter { $0.name == "cannon" }
        let x = paddleHalfWidth - 12
        for (i, c) in cannons.enumerated() { c.position = CGPoint(x: i == 0 ? -x : x, y: 14) }
    }
    func removeLaserCannons() {
        paddle.children.filter { $0.name == "cannon" }.forEach { $0.removeFromParent() }
    }
    func fireLasers() {
        if soundOn, let snd = NSSound(named: "Tink")?.copy() as? NSSound { snd.volume = 0.25; snd.play() }
        let x = paddleHalfWidth - 12
        for dx in [-x, x] {
            let beam = SKSpriteNode(color: .systemRed, size: CGSize(width: 5, height: 20))
            let core = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 16))
            beam.addChild(core)
            beam.position = CGPoint(x: paddle.position.x + dx, y: paddle.position.y + 26)
            beam.zPosition = 14
            addChild(beam)
            lasers.append(beam)
        }
    }
    func updateLasers(_ step: CGFloat) {
        for beam in lasers {
            beam.position.y += laserSpeed * step
            if beam.position.y > size.height - 60 { beam.removeFromParent(); continue }
            let tip = CGPoint(x: beam.position.x, y: beam.position.y + 10)
            if let brick = children.first(where: { $0.name == "brick" && $0.frame.contains(tip) }) {
                beam.removeFromParent()
                if !damageBrick(brick) {          // klods med flere lag: mister kun et lag
                    addPoints(1, at: brick.position)
                    playHitSound()
                    continue
                }
                addPoints(2, at: brick.position)
                maybeDropPowerUp(at: brick.position)
                makeBrickFall(brick)
                playHitSound()
                updateHUD()
                checkLevelCleared()
                if !isPlaying { break }   // baneskift – resten ryddes af removeCapsulesAndLasers()
            }
        }
        lasers.removeAll { $0.parent == nil }
    }

    // MARK: Skjold
    func createShield() {
        childNode(withName: "shield")?.removeFromParent()
        let shield = SKShapeNode(rect: CGRect(x: 0, y: shieldY - 3, width: size.width, height: 6), cornerRadius: 3)
        shield.name = "shield"
        shield.fillColor = SKColor.systemGreen.withAlphaComponent(0.7)
        shield.strokeColor = .white; shield.lineWidth = 1; shield.glowWidth = 6
        shield.zPosition = 5
        shield.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: shieldY), to: CGPoint(x: size.width, y: shieldY))
        shield.physicsBody?.categoryBitMask = PhysicsCategory.wall
        shield.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.5), .fadeAlpha(to: 1.0, duration: 0.5)])))
        addChild(shield)
    }
    /// En bold rammer skjoldet: bolden sendes op igen, og skjoldet går i stykker
    func handleShieldHit(_ ball: SKShapeNode) {
        let speed = currentSpeed()
        let angle = CGFloat.random(in: 35...145) * .pi / 180
        ball.physicsBody?.velocity = CGVector(dx: cos(angle) * speed, dy: abs(sin(angle) * speed))
        guard shieldActive else { return }
        shieldActive = false
        if soundOn { NSSound(named: "Glass")?.play() }
        explode(at: CGPoint(x: ball.position.x, y: shieldY), color: .systemGreen)
        floatingText("SHIELD SAVED YOU!", at: CGPoint(x: ball.position.x, y: shieldY + 70), color: .systemGreen)
        if let shield = childNode(withName: "shield") {
            shield.name = nil
            shield.removeAllActions()
            shield.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        updatePowerUpLabel()
    }

    // MARK: Oprydning
    /// Fjerner kapsler og laserskud i luften (ved baneskift)
    func removeCapsulesAndLasers() {
        capsules.forEach { $0.removeFromParent() }
        lasers.forEach { $0.removeFromParent() }
        capsules.removeAll(); lasers.removeAll()
    }
    /// Nulstiller alle power-ups (ved nyt spil)
    func clearPowerUps() {
        removeCapsulesAndLasers()
        wideRemaining = 0; slowRemaining = 0; laserRemaining = 0; laserCooldown = 0
        removeLaserCannons()
        shieldActive = false
        childNode(withName: "shield")?.removeFromParent()
        refreshPaddleShape()
        updatePowerUpLabel()
    }

    // MARK: Visning nederst til venstre
    func setupPowerUpHUD() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 12
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 12, y: 8)
        label.zPosition = 30
        addChild(label)
        powerUpLabel = label
    }
    func updatePowerUpLabel() {
        guard let label = powerUpLabel else { return }
        var parts: [String] = []
        if wideRemaining > 0 { parts.append("WIDE \(Int(ceil(wideRemaining)))s") }
        if slowRemaining > 0 { parts.append("SLOW \(Int(ceil(slowRemaining)))s") }
        if laserRemaining > 0 { parts.append("LASER \(Int(ceil(laserRemaining)))s") }
        if shieldActive { parts.append("SHIELD") }
        let text = parts.joined(separator: "   ")
        if label.text != text { label.text = text }
        label.fontColor = .white
    }
}
