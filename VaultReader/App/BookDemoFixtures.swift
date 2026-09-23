#if DEBUG
import UIKit

@MainActor enum BookDemoFixtures {
    static var markdown: [(String, String)] {
        let original = "# 夜航手记\n\n" + ["第一章 出发", "第二章 灯塔", "第三章 归途"].map { title in
            "## \(title)\n\n" + String(repeating: "船从安静的港口出发。我们把灯光和远处的岸线记在纸上，每一页都留下一段可以回来的路。\n\n", count: 24)
        }.joined()
        return [
            ("read/书单.md", "# 书单\n\n## 在读\n\n### 夜航手记\n- 作者：示例作者\n- 状态：在读\n- 原书：[PDF](../files/夜航手记.pdf)（合成的五页样书）\n- 全文：[[夜航手记-原文|原文]]\n- 精简版：[[夜航手记-精简版|精简版]]\n- 评论：合成的短评，不含私人内容。\n"),
            ("read/夜航手记/夜航手记-原文.md", original),
            ("read/夜航手记/夜航手记-精简版.md", "# 夜航手记精简版\n\n## 启程\n\n简短的独立版本。\n\n## 回港\n\n在灯光下结束阅读。"),
            ("articles/观察与记录.md", "# 观察与记录\n\n## 观察\n\n" + String(repeating: "从日常的观察里记下一点新的发现。\n\n", count: 20))
        ]
    }
    static var pdf: Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 600)).pdfData { context in
            for page in 1...5 {
                context.beginPage()
                ("Night Voyage — Page \(page)" as NSString).draw(at: CGPoint(x: 36,y: 45), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
                ("Synthetic reading fixture.\nNo private book content." as NSString).draw(at: CGPoint(x: 36,y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        }
    }
}
#endif
