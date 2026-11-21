import SpriteKit
import AppKit

// MARK: - Klodser med 3 lag
// Fra level 2 får ca. hver 8. klods 3 lag. Den har en sølvkant og et tal,
// der viser hvor mange slag den mangler. Hvert slag (bold nedefra eller laserskud)
// fjerner et lag, giver +1 point og laver en revne. Ved sidste slag går den i stykker som normalt.

extension GameScene {
    var armoredChance: Double { 0.12 }   // andel af klodserne der får 3 lag
    var armoredHits: Int { 3 }

    /// Gør tilfældige klodser på banen til 3-lags-klodser (kaldes når klodserne bygges)
    func addArmoredBricks() {
        guard level >= 2 else { return }
        for brick in children where brick.name == "brick" {
            if Double.random(in: 0..<1) < armoredChance { makeArmored(brick) }
        }
    }

    func makeArmored(_ brick: SKNode) {
        if brick.userData == nil { brick.userData = NSMutableDictionary() }
        brick.userData?["hits"] = armoredHits
        let silver = SKColor(white: 0.92, alpha: 1)
        if let shape = brick as? SKShapeNode {
            shape.strokeColor = silver
            shape.lineWidth = 3
        } else if let sprite = brick as? SKSpriteNode {
            let rim = SKShapeNode(rectOf: sprite.size, cornerRadius: 5)
            rim.name = "armorRim"
            rim.strokeColor = silver; rim.lineWidth = 3; rim.fillColor = .clear
            rim.zPosition = 3
            sprite.addChild(rim)
        }
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = "hitsLabel"
        label.text = "\(armoredHits)"
        label.fontSize = 13; label.fontColor = .white
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        label.zPosition = 5
        let shadow = SKLabelNode(fontNamed: "Menlo-Bold")
        shadow.text = label.text; shadow.fontSize = 13; shadow.fontColor = .black
        shadow.verticalAlignmentMode = .center; shadow.horizontalAlignmentMode = .center
        shadow.position = CGPoint(x: 1, y: -1); shadow.zPosition = -1
        shadow.name = "hitsShadow"
        label.addChild(shadow)
        brick.addChild(label)
    }

    func hitsLeft(_ brick: SKNode) -> Int { (brick.userData?["hits"] as? Int) ?? 1 }

    /// Rammer en klods. Returnerer true hvis den skal gå i stykker,
    /// false hvis den kun mistede et lag (så bliver den hængende)
    func damageBrick(_ brick: SKNode) -> Bool {
        let hits = hitsLeft(brick)
        guard hits > 1 else { return true }
        let left = hits - 1
        brick.userData?["hits"] = left
        if let label = brick.childNode(withName: "hitsLabel") as? SKLabelNode {
            label.text = "\(left)"
            (label.childNode(withName: "hitsShadow") as? SKLabelNode)?.text = "\(left)"
            label.run(.sequence([.scale(to: 1.6, duration: 0.08), .scale(to: 1.0, duration: 0.15)]))
        }
        addCrack(to: brick)
        // blink og lille ryst
        brick.run(.sequence([.fadeAlpha(to: 0.45, duration: 0.05), .fadeAlpha(to: 1.0, duration: 0.12)]))
        brick.run(.sequence([.moveBy(x: 3, y: 0, duration: 0.03), .moveBy(x: -6, y: 0, duration: 0.05), .moveBy(x: 3, y: 0, duration: 0.03)]))
        chipSparks(at: brick.position)
        return false
    }

    /// Tegner en zigzag-revne hen over klodsen
    func addCrack(to brick: SKNode) {
        let w = max(brick.frame.width * 0.38, 6), h = max(brick.frame.height * 0.38, 6)
        let path = CGMutablePath()
        var p = CGPoint(x: CGFloat.random(in: -w...w), y: h)
        path.move(to: p)
        for i in 1...4 {
            p = CGPoint(x: p.x + CGFloat.random(in: -w/2...w/2), y: h - CGFloat(i) * h / 2)
            path.addLine(to: p)
        }
        let crack = SKShapeNode(path: path)
        crack.name = "crack"
        crack.strokeColor = SKColor(white: 0, alpha: 0.75)
        crack.lineWidth = 1.8
        crack.zPosition = 4
        brick.addChild(crack)
    }

    /// Små skår der springer af, når en klods mister et lag
    func chipSparks(at pos: CGPoint) {
        for _ in 0..<7 {
            let chip = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3))
            chip.fillColor = SKColor(white: 0.9, alpha: 1); chip.strokeColor = .clear
            chip.position = pos; chip.zPosition = 21
            addChild(chip)
            let a = CGFloat.random(in: 0...(2 * .pi)), d = CGFloat.random(in: 15...40)
            chip.run(.sequence([.group([.moveBy(x: cos(a) * d, y: sin(a) * d - 10, duration: 0.3),
                                        .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        }
    }
}
