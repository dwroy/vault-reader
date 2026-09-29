import XCTest
import Darwin
import VaultCore

/// Explicit opt-in, synthetic-only benchmark. Its temporary cache never touches saved vaults.
final class SearchDevicePerformanceTests: XCTestCase {
    private struct Corpus: Sendable {
        let entries: [TreeEntry]
        let bodies: [(TreeEntry, Data)]
    }
    private struct Phase: Codable {
        let name: String
        let wallMS: Double
        let cpuMS: Double
        let averageCPUPercent: Double
        let startFootprintMiB: Double
        let endFootprintMiB: Double
        let sampledPeakFootprintMiB: Double
        let processPeakRSSMiB: Double
        let mainActorGapP95MS: Double
        let mainActorGapMaxMS: Double
        let queries: Int
        let queryP50MS: Double
        let queryP95MS: Double
        let queryMaxMS: Double
        let indexed: Int
        let metadataOnly: Int
        let pending: Int
        let accountedBodyMiB: Double
        let restored: Int
        let built: Int
    }
    @MainActor private final class Sampler {
        var gaps: [Double] = []
        var peak = footprint()
        var task: Task<Void, Never>?
        func start() {
            task = Task { [weak self] in
                var last = ContinuousClock.now
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                    guard let self else { return }
                    let now = ContinuousClock.now
                    gaps.append(milliseconds(last.duration(to: now))); last = now
                    peak = max(peak, footprint())
                }
            }
        }
        func stop() { task?.cancel(); task = nil; peak = max(peak, footprint()) }
    }
    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }
    private static func usage() -> (cpu: Double, rss: Double) {
        var value = rusage(); getrusage(RUSAGE_SELF, &value)
        let seconds = Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
        let microseconds = Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec)
        return (seconds * 1000 + microseconds / 1000, Double(value.ru_maxrss) / 1024 / 1024)
    }
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1024 / 1024 : -1
    }
    private static func corpus() -> Corpus {
        let unit = "## Synthetic section\n\n公园慢慢散步 **readable** words for measurement.\n\n"
        let base = String(repeating: unit, count: 16 * 1024 / unit.utf8.count)
        var bodies: [(TreeEntry, Data)] = []
        for i in 0..<400 {
            let data = Data(("# Document \(i)\n\n" + base).utf8)
            bodies.append((TreeEntry(path: "notes/\(i).md", sha: BlobStore.hash(data), size: data.count), data))
        }
        let ready = Data("ready marker".utf8)
        bodies.insert((TreeEntry(path: "ready.md", sha: BlobStore.hash(ready), size: ready.count), ready), at: 0)
        let images = (0..<5000).map { TreeEntry(path: "photos/photo-\($0).jpg", sha: "photo-\($0)", size: 4_000_000) }
        let large = [1, 8].map { TreeEntry(path: "large-\($0)MiB.md", sha: "large-\($0)", size: $0 * 1024 * 1024) }
        return Corpus(entries: bodies.map(\.0) + images + large, bodies: bodies)
    }
    @MainActor private func phase(_ name: String, engine: SearchIndex, requiresReadyMarker: Bool = true, work: @escaping @Sendable () async throws -> Void) async throws -> Phase {
        let sampler = Sampler(); sampler.start()
        let start = ContinuousClock.now, before = SearchDevicePerformanceTests.usage(), initialFootprint = SearchDevicePerformanceTests.footprint()
        let queries = Task.detached(priority: .userInitiated) { () throws -> [Double] in
            var values: [Double] = []
            let terms = requiresReadyMarker ? ["ready", "公园 慢慢", "图片", "absent-query-marker"] : ["md", "的", "text", "absent-query-marker"]
            while !Task.isCancelled {
                let tick = ContinuousClock.now
                do {
                    let hits = try await engine.searchResults(terms[values.count % terms.count])
                    if requiresReadyMarker && values.count % terms.count == 0 && !hits.hits.contains(where: { $0.path == "ready.md" }) {
                        throw NSError(domain: "SearchBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Existing ready result disappeared during preparation"])
                    }
                    values.append(SearchDevicePerformanceTests.milliseconds(tick.duration(to: .now)))
                    try await Task.sleep(for: .milliseconds(50))
                } catch is CancellationError { break }
            }
            return values
        }
        do { try await work() } catch { queries.cancel(); sampler.stop(); throw error }
        let wall = SearchDevicePerformanceTests.milliseconds(start.duration(to: .now)), after = SearchDevicePerformanceTests.usage()
        queries.cancel(); let latency = try await queries.value; sampler.stop()
        let coverage = await engine.coverage, diagnostics = await engine.diagnostics
        return Phase(name: name, wallMS: wall, cpuMS: after.cpu - before.cpu,
                     averageCPUPercent: (after.cpu - before.cpu) / max(wall, 1) * 100,
                     startFootprintMiB: initialFootprint, endFootprintMiB: SearchDevicePerformanceTests.footprint(), sampledPeakFootprintMiB: sampler.peak, processPeakRSSMiB: after.rss,
                     mainActorGapP95MS: SearchDevicePerformanceTests.percentile(sampler.gaps, 0.95), mainActorGapMaxMS: sampler.gaps.max() ?? 0,
                     queries: latency.count, queryP50MS: SearchDevicePerformanceTests.percentile(latency, 0.5), queryP95MS: SearchDevicePerformanceTests.percentile(latency, 0.95), queryMaxMS: latency.max() ?? 0,
                     indexed: coverage.indexed, metadataOnly: coverage.metadataOnly, pending: coverage.pending,
                     accountedBodyMiB: Double(coverage.residentBytes) / 1024 / 1024,
                     restored: diagnostics.restoredDocuments, built: diagnostics.builtDocuments)
    }
    @MainActor func testIsolatedDeviceSearchPerformance() async throws {
        guard ProcessInfo.processInfo.environment["VR_RUN_SEARCH_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt in with VR_RUN_SEARCH_BENCHMARK=1 on the test host")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SearchBenchmark-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let maker = Task.detached(priority: .utility) { @Sendable () -> Corpus in SearchDevicePerformanceTests.corpus() }
        let corpus = await maker.value
        var phases: [Phase] = []
        var catalogMS = 0.0
        do {
            let engine = SearchIndex(cacheDirectory: root)
            let start = ContinuousClock.now
            await engine.update(corpus.entries); catalogMS = SearchDevicePerformanceTests.milliseconds(start.duration(to: .now))
            await engine.insert(data: corpus.bodies[0].1, for: corpus.bodies[0].0)
            phases.append(try await phase("cold-400-markdown-plus-5000-images", engine: engine) {
                for (entry, data) in corpus.bodies.dropFirst() { await engine.insert(data: data, for: entry) }
            })
            let coverage = await engine.coverage
            XCTAssertEqual(coverage.indexed, 401); XCTAssertEqual(coverage.metadataOnly, 5002); XCTAssertEqual(coverage.pending, 0)
        }
        do {
            let engine = SearchIndex(cacheDirectory: root)
            await engine.update(corpus.entries); _ = await engine.restoreCachedText(for: corpus.bodies[0].0)
            phases.append(try await phase("warm-derived-cache-restore", engine: engine) {
                for (entry, _) in corpus.bodies.dropFirst() { _ = await engine.restoreCachedText(for: entry) }
            })
            let diagnostics = await engine.diagnostics
            XCTAssertEqual(diagnostics.restoredDocuments, 401); XCTAssertEqual(diagnostics.builtDocuments, 0)
            phases.append(try await phase("fully-ready-search-3-seconds", engine: engine) {
                try await Task.sleep(for: .seconds(3))
            })
        }
        do {
            let engine = SearchIndex()
            let unit = "## Heading\n\n公园 **words** for boundary parsing.\n\n"
            let data = Data(String(repeating: unit, count: 512 * 1024 / unit.utf8.count).utf8)
            let boundary = TreeEntry(path: "boundary.md", sha: BlobStore.hash(data), size: data.count)
            await engine.update([corpus.bodies[0].0, boundary]); await engine.insert(data: corpus.bodies[0].1, for: corpus.bodies[0].0)
            phases.append(try await phase("512-KiB-boundary-markdown", engine: engine) { await engine.insert(data: data, for: boundary) })
            let count = await engine.count; XCTAssertEqual(count, 2)
        }
        do {
            let engine = SearchIndex()
            let entries = (0..<6000).map { TreeEntry(path: String(format: "budget/%05d.txt", $0), sha: "budget-\($0)", size: 32 * 1024) }
            await engine.update(entries + [corpus.bodies[0].0], preferredPath: "ready.md")
            await engine.insert(data: corpus.bodies[0].1, for: corpus.bodies[0].0)
            phases.append(try await phase("6000-files-body-capacity", engine: engine) {
                let data = Data(String(repeating: "Text capacity sample.\n", count: 1500).utf8)
                for entry in entries {
                    if !(await engine.needsBody(for: entry)) { break }
                    await engine.insert(data: data, for: entry)
                }
            })
            let coverage = await engine.coverage
            XCTAssertGreaterThan(coverage.limited, 1000); XCTAssertEqual(coverage.pending, 0)
            XCTAssertLessThanOrEqual(coverage.residentBytes, engine.limits.residentBytes)
        }
        struct Report: Codable {
            let os: String, optimization: String, thermalStateStart: Int, thermalStateEnd: Int
            let catalogFiles: Int, catalogMS: Double, phases: [Phase]
        }
        let report = Report(os: ProcessInfo.processInfo.operatingSystemVersionString, optimization: "Record compiler flags with this report", thermalStateStart: initialThermalState, thermalStateEnd: ProcessInfo.processInfo.thermalState.rawValue, catalogFiles: corpus.entries.count, catalogMS: catalogMS, phases: phases)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "device-search-performance"; attachment.lifetime = .keepAlways; add(attachment)
        print("SEARCH_DEVICE_PERFORMANCE " + String(decoding: data, as: UTF8.self))
    }
    /// Reads only already-cached source blobs. No credentials, network, source deletion or content output.
    @MainActor func testExistingVaultCachedSourcePerformance() async throws {
        guard ProcessInfo.processInfo.environment["VR_RUN_EXISTING_VAULT_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt in separately to benchmark the saved vault's existing local source cache")
        }
        guard let saved = UserDefaults.standard.data(forKey: "repository"),
              let config = try? JSONDecoder().decode(RepositoryConfig.self, from: saved) else { throw XCTSkip("No saved repository") }
        let sourceRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VaultReader").appendingPathComponent(MetaStore.key(config.identity))
        let meta = try MetaStore(root: sourceRoot.appendingPathComponent("meta").appendingPathComponent(MetaStore.key(config.branch)))
        guard let tree = try await meta.read("tree", as: GitTree.self), !tree.truncated else { throw XCTSkip("No complete cached tree") }
        let files = VaultIndex(tree.tree).entries, blobs = try BlobStore(root: sourceRoot.appendingPathComponent("blobs"))
        let derived = FileManager.default.temporaryDirectory.appendingPathComponent("ExistingVaultBenchmark-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: derived) }
        var phases: [Phase] = []
        do {
            let engine = SearchIndex(cacheDirectory: derived)
            await engine.update(files, preferredPath: config.home)
            let candidates = await engine.bodyCandidates(preferredPath: config.home)
            phases.append(try await phase("existing-vault-cached-source-cold", engine: engine, requiresReadyMarker: false) {
                for entry in candidates {
                    guard await engine.needsBody(for: entry) else { continue }
                    do {
                        if let data = try await blobs.data(for: entry.sha, maximumBytes: engine.limits.sourceBytes) { await engine.insert(data: data, for: entry) }
                    } catch VaultError.tooLarge { await engine.excludeOversized(entry) }
                    catch { continue }
                }
            })
        }
        do {
            let engine = SearchIndex(cacheDirectory: derived); await engine.update(files, preferredPath: config.home)
            let candidates = await engine.bodyCandidates(preferredPath: config.home)
            phases.append(try await phase("existing-vault-temporary-derived-restore", engine: engine, requiresReadyMarker: false) {
                for entry in candidates { _ = await engine.restoreCachedText(for: entry) }
            })
            phases.append(try await phase("existing-vault-ready-search-3-seconds", engine: engine, requiresReadyMarker: false) { try await Task.sleep(for: .seconds(3)) })
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(phases)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "existing-cached-vault-performance-counts-only"; attachment.lifetime = .keepAlways; add(attachment)
        print("EXISTING_VAULT_PERFORMANCE " + String(decoding: data, as: UTF8.self))
    }
    private let initialThermalState = ProcessInfo.processInfo.thermalState.rawValue
}
