import SwiftUI

/// The pane's own copy of the Input Devices list, for a pane with nothing
/// to show — no camera picked, a camera that failed, a tablet unplugged.
/// The same picks as the menu bar's, through the same `InputDevices`, so a
/// tablet picked here turns the camera off and a camera picked here gives
/// the pane back to the video, exactly as there.
struct InputDevicePicker: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var tablet: TabletController

    var body: some View {
        Menu {
            if camera.devices.isEmpty {
                Text("No cameras found")
            }
            ForEach(camera.devices) { device in
                Button {
                    InputDevices.pick(cameraID: device.id, cameras: camera, tablets: tablet)
                } label: {
                    HStack {
                        Text(device.name)
                        if camera.selectedDeviceID == device.id { Image(systemName: "checkmark") }
                    }
                }
            }
            if !tablet.tablets.isEmpty {
                Divider()
                Text("Tablets")
                ForEach(tablet.tablets) { device in
                    Button {
                        InputDevices.pick(device, cameras: camera, tablets: tablet)
                    } label: {
                        HStack {
                            Text(device.name)
                            if tablet.selectedTabletID == device.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Divider()
            Button("Refresh Device List") { camera.refreshDevices() }
        } label: {
            Label("Input Devices", systemImage: "video.badge.ellipsis")
        }
        .fixedSize()
    }
}
