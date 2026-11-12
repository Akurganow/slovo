/// A loadable speech model. Loading is expensive (a first run downloads it, every load
/// compiles it for the device), so a loaded model stays loaded until the process exits.
public protocol ModelLoading: AnyObject {
    func load() async throws
    var isLoaded: Bool { get }
}
