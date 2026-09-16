import SwiftUI
import MapKit

struct PlacesBrowser: View {
    let client: ImmichClient
    let onSelect: (ImmichAsset) -> Void
    @State private var pins: [PlacePin] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Places…")
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn’t Load Places", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if pins.isEmpty {
                ContentUnavailableView("No Location Data", systemImage: "map",
                    description: Text("Photos with GPS coordinates will appear here."))
            } else {
                AssetMap(pins: pins, onSelect: onSelect)
                    .overlay(alignment: .bottomLeading) {
                        Text("Showing locations from the newest \(pins.count) photos")
                            .font(.caption).padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule()).padding(14)
                    }
            }
        }
        .navigationTitle("Places")
        .toolbar {
            Button { Task { await load() } } label: { Label("Refresh Places", systemImage: "arrow.clockwise") }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { pins = try await client.locationAssets().compactMap(PlacePin.init(asset:)) }
        catch { self.error = error.localizedDescription }
    }
}

struct PlacePin: Identifiable {
    let asset: ImmichAsset
    let coordinate: CLLocationCoordinate2D
    var id: String { asset.id }
    init?(asset: ImmichAsset) {
        guard let latitude = asset.exifInfo?.latitude, let longitude = asset.exifInfo?.longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.asset = asset
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct AssetMap: NSViewRepresentable {
    let pins: [PlacePin]
    let onSelect: (ImmichAsset) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    func makeNSView(context: Context) -> MKMapView {
        let view = MKMapView(); view.delegate = context.coordinator; view.pointOfInterestFilter = .includingAll; return view
    }
    func updateNSView(_ view: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        view.removeAnnotations(view.annotations)
        let annotations = pins.map { AssetAnnotation(pin: $0) }
        view.addAnnotations(annotations)
        if !annotations.isEmpty { view.showAnnotations(annotations, animated: false) }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (ImmichAsset) -> Void
        init(onSelect: @escaping (ImmichAsset) -> Void) { self.onSelect = onSelect }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? AssetAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "asset")
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "asset")
            view.annotation = annotation; view.canShowCallout = true
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? AssetAnnotation else { return }
            onSelect(annotation.pin.asset)
        }
    }
}

private final class AssetAnnotation: NSObject, MKAnnotation {
    let pin: PlacePin
    dynamic var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.asset.originalFileName }
    init(pin: PlacePin) { self.pin = pin }
}
