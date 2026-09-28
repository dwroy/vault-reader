import Foundation

/// Original, synthetic documents. UI localization never translates a user's repository.
enum EnglishSamples {
    static var files: [(String, String)] {
        let book = "# Night Voyage\n\n" + ["Chapter 1: Departure", "Chapter 2: The Lighthouse", "Chapter 3: Homeward"].map { heading in
            "## \(heading)\n\n" + String(repeating: "We left the quiet harbor and wrote down the lights along the distant shore. Each page keeps a place we can return to.\n\n", count: 24)
        }.joined()
        return [
            ("README.md", """
            ---
            tags: [reading, local-first]
            booklist: Books/Booklist.md
            ---
            # Your knowledge, ready to read

            Notes, reports and books in one portable library.

            ## Start here
            - [[Notes/A day in the park|Small moments worth keeping]]
            - [[Books/Booklist|Books and reading notes]]
            - [[Guide|Markdown, HTML and PDF]]

            ## AI Native
            Organize files with your preferred AI tools on your computer. Open them here whenever you want to read.

            > These are original sample documents. Connect your own GitHub or GitLab repository to read your files.
            """),
            ("Notes/A day in the park.md", "# A day in the park\n\nA small leaf looked like a boat. We stopped to take a closer look.\n\n![[files/leaf.svg|300]]\n\n==Ordinary moments are worth remembering.==\n\n## On the way home\n- [x] Notice the leaves\n- [ ] Bring a sketchbook next time\n\n[[README|Back to the library]]"),
            ("Guide.md", "# Read your own knowledge base\n\nOpen **Markdown**, HTML and PDF directly in Vault Reader. Files are read-only.\n\n## Files and links\nFollow [[README|wikilinks]], read tables and code, or open an image.\n\n[[Missing note]] is shown as a missing link.\n\n```swift\nlet reading = true\n```\n\n## Other formats\n- [Interactive HTML](Reader.html)\n- [Sample PDF](files/Night%20Voyage.pdf)\n\n## Offline and resume\nCached documents remain available offline. Your reading position is stored on this device.\n"),
            ("Reader.html", "<!doctype html><html lang='en'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font:22px -apple-system;padding:24px;color-scheme:light dark}button{font:inherit;padding:15px;margin:10px}</style><h1>Independent HTML reader</h1><p id='page'></p><button onclick='n++;save()'>Next page</button><button onclick='n=1;save()'>Reset</button><script>let n=Number(localStorage.getItem('page')||1);function save(){localStorage.setItem('page',n);document.getElementById('page').textContent='Page '+n}save()</script></html>"),
            ("Books/Booklist.md", "# My book list\n\n## Reading now\n\n### Night Voyage\n- author: Sample author\n- status: Reading\n- original: [PDF](../files/Night%20Voyage.pdf) (five synthetic pages)\n- fulltext: [[Night Voyage-Full text|Full text]]\n- condensed: [[Night Voyage-Summary|Summary]]\n- review: An original sample review with no private content.\n"),
            ("read/Night Voyage/Night Voyage-Full text.md", book),
            ("read/Night Voyage/Night Voyage-Summary.md", "# Night Voyage: summary\n\n## Setting out\n\nA short, independent edition.\n\n## Returning home\n\nA quiet end to the day's reading."),
            ("articles/Observations.md", "# Observations\n\n## Look closely\n\n" + String(repeating: "Write down a new detail from an ordinary day.\n\n", count: 20)),
            ("Notes/مرحبا.md", "# مرحبًا\n\nهذه ملاحظة تجريبية باللغة العربية. يحتفظ كل مستند بلغته الأصلية، ويمكن قراءة العربية والإنجليزية في المكتبة نفسها.\n\n## نص وكود\n\n```swift\nlet path = \"notes/example.md\"\n```\n\n[Back to the library](../README.md)"),
            ("Notes/नमस्ते.md", "# नमस्ते\n\nयह हिन्दी में एक नमूना दस्तावेज़ है। हर दस्तावेज़ अपनी मूल भाषा में रहता है। एक ही लाइब्रेरी में हिन्दी और अंग्रेज़ी पढ़ें।\n\n## टेक्स्ट और कोड\n\n```swift\nlet path = \"notes/example.md\"\n```\n\n[Back to the library](../README.md)")
        ]
    }
}
