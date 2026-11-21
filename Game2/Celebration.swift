import SpriteKit
import AppKit

// MARK: - Fejring når en level er klaret
// Spillet stopper i ca. 3 sekunder: fanfare (fanfare.wav), stor regnbue-tekst,
// tre stjerner og fyrværkeri over hele skærmen. Derefter starter næste level.
// Fanfaren kan skiftes ud ved at lægge en anden fil med navnet fanfare.wav i Game2-mappen.

extension GameScene {
    var celebrationDuration: TimeInterval { 3.0 }

    func startCelebration(level clearedLevel: Int) {
        stopCelebration()
        let layer = SKNode()
        layer.name = "celebration"
        layer.zPosition = 60
        addChild(layer)
        playFanfare()

        // Stor titel, der popper ind og skifter gennem regnbuens farver
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "LEVEL \(clearedLevel) COMPLETE!"
        title.fontSize = min(48, size.width / 16)
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
        title.setScale(0.1)
        layer.addChild(title)
        let pop = SKAction.sequence([.scale(to: 1.25, duration: 0.25), .scale(to: 0.95, duration: 0.12), .scale(to: 1.0, duration: 0.1)])
        let pulse = SKAction.repeatForever(.sequence([.scale(to: 1.06, duration: 0.35), .scale(to: 1.0, duration: 0.35)]))
        title.run(.sequence([pop, pulse]))
        let rainbow = brickColors
        title.run(.repeatForever(.customAction(withDuration: 1.4) { node, t in
            guard let label = node as? SKLabelNode else { return }
            let pos = t / 1.4 * CGFloat(rainbow.count)
            let i = Int(pos) % rainbow.count
            label.fontColor = rainbow[i].blended(withFraction: pos - floor(pos), of: rainbow[(i + 1) % rainbow.count]) ?? rainbow[i]
        }))

        // Tre stjerner der dukker op en ad gangen
        for i in 0..<3 {
            let star = SKLabelNode(text: "★")
            star.fontSize = 46; star.fontColor = .systemYellow
            star.verticalAlignmentMode = .center
            star.position = CGPoint(x: size.width / 2 + CGFloat(i - 1) * 70, y: size.height * 0.6 - 70)
            star.setScale(0); star.zRotation = -0.6
            layer.addChild(star)
            star.run(.sequence([.wait(forDuration: 0.5 + Double(i) * 0.3),
                                .group([.scale(to: 1.0, duration: 0.25), .rotate(toAngle: 0, duration: 0.25)])]))
        }

        // Fyrværkeri
        let rockets = 11
        for i in 0..<rockets {
            layer.run(.sequence([.wait(forDuration: Double(i) * 0.24),
                                 .run { [weak self] in self?.launchFirework(in: layer) }]))
        }
        layer.run(.sequence([.wait(forDuration: celebrationDuration + 0.2), .removeFromParent()]))
    }

    /// Stopper fejringen med det samme (fx ved nyt spil)
    func stopCelebration() {
        childNode(withName: "celebration")?.removeFromParent()
        fanfareSound?.stop()
        fanfareSound = nil
    }

    func playFanfare() {
        guard soundOn, let snd = NSSound(named: "fanfare")?.copy() as? NSSound else { return }
        fanfareSound = snd
        snd.play()
    }

    /// En raket stiger op og eksploderer i en farverig stjerne
    func launchFirework(in layer: SKNode) {
        let target = CGPoint(x: CGFloat.random(in: size.width * 0.1...size.width * 0.9),
                             y: CGFloat.random(in: size.height * 0.35...size.height * 0.85))
        let color = SKColor(hue: .random(in: 0...1), saturation: 0.85, brightness: 1, alpha: 1)
        let rocket = SKShapeNode(circleOfRadius: 3)
        rocket.fillColor = .white; rocket.strokeColor = .clear; rocket.glowWidth = 4
        rocket.position = CGPoint(x: target.x + CGFloat.random(in: -40...40), y: 0)
        layer.addChild(rocket)
        let rise = SKAction.move(to: target, duration: 0.45)
        rise.timingMode = .easeOut
        rocket.run(.sequence([rise, .run { [weak self, weak layer] in
            guard let self, let layer else { return }
            self.burst(at: target, color: color, in: layer)
        }, .removeFromParent()]))
    }

    func burst(at pos: CGPoint, color: SKColor, in layer: SKNode) {
        let flash = SKShapeNode(circleOfRadius: 14)
        flash.fillColor = .white; flash.strokeColor = .clear; flash.glowWidth = 10
        flash.position = pos
        layer.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 2.5, duration: 0.15), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
        let second = color.blended(withFraction: 0.5, of: .white) ?? .white
        let count = 34
        for i in 0..<count {
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...3.5))
            spark.fillColor = i % 3 == 0 ? second : color
            spark.strokeColor = .clear; spark.glowWidth = 2
            spark.position = pos
            layer.addChild(spark)
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.08...0.08)
            let d = CGFloat.random(in: 90...150)
            let out = SKAction.moveBy(x: cos(a) * d, y: sin(a) * d, duration: 0.6)
            out.timingMode = .easeOut
            let drop = SKAction.moveBy(x: 0, y: -45, duration: 0.6)
            drop.timingMode = .easeIn
            spark.run(.sequence([out, .group([drop, .fadeOut(withDuration: 0.6), .scale(to: 0.3, duration: 0.6)]), .removeFromParent()]))
        }
    }
}
