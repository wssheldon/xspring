use eframe::egui;
use egui::{Color32, Pos2, Rect, Response, RichText, Sense, Stroke, Ui, Vec2};
use walkers::{sources::OpenStreetMap, HttpTiles, Map, MapMemory, Plugin, Position, Projector};

use crate::gui::client::GuiClient;
use crate::models::Beacon;
use egui_phosphor::regular;

/// Plugin for displaying beacons on the map
struct BeaconMapPlugin<'a> {
    beacons: &'a [Beacon],
}

impl<'a> BeaconMapPlugin<'a> {
    fn new(beacons: &'a [Beacon]) -> Self {
        Self { beacons }
    }
}

impl Plugin for BeaconMapPlugin<'_> {
    fn run(self: Box<Self>, ui: &mut Ui, response: &Response, projector: &Projector) {
        let painter = ui.painter();

        for beacon in self.beacons {
            let pos = Position::new(beacon.longitude, beacon.latitude);
            let screen_pos = projector.project(pos);

            // Draw beacon marker
            let marker_radius = 5.0;
            let marker_pos = Pos2::new(screen_pos.x, screen_pos.y);

            // Draw a red circle for the beacon
            painter.circle_filled(marker_pos, marker_radius, Color32::RED);

            // Add hover detection and tooltip
            let marker_rect = Rect::from_center_size(marker_pos, Vec2::splat(marker_radius * 2.0));

            if response.rect.contains(marker_pos) && ui.rect_contains_pointer(marker_rect) {
                egui::show_tooltip(
                    ui.ctx(),
                    response.layer_id,
                    response.id.with("beacon_tooltip"),
                    |ui| {
                        ui.label(format!("ID: {}", beacon.id));
                        ui.label(format!("Status: {}", beacon.status));
                        ui.label(format!("Last Seen: {}", beacon.last_seen));
                        ui.label(format!(
                            "Hostname: {}",
                            beacon.hostname.as_deref().unwrap_or("Unknown")
                        ));
                        ui.label(format!(
                            "Username: {}",
                            beacon.username.as_deref().unwrap_or("Unknown")
                        ));
                        ui.label(format!(
                            "OS: {}",
                            beacon.os_version.as_deref().unwrap_or("Unknown")
                        ));
                    },
                );
            }
        }
    }
}

impl GuiClient {
    pub fn render_dashboard_view(&mut self, ui: &mut Ui) {
        // Create a frame for the dashboard
        egui::Frame::new()
            .fill(egui::Color32::from_rgb(20, 20, 20))
            .show(ui, |ui| {
                // Add title
                ui.vertical(|ui| {
                    ui.add_space(10.0);
                    ui.heading(RichText::new(format!("{} Dashboard", regular::CHART_LINE)));
                    ui.add_space(10.0);
                    ui.separator();
                    ui.add_space(10.0);

                    // Create beacon data first so it lives longer than map
                    let beacons_data: Vec<Beacon> = if let Ok(beacons) = self.beacons.try_lock() {
                        beacons.clone()
                    } else {
                        Vec::new()
                    };

                    // Create the plugin first
                    let plugin = BeaconMapPlugin::new(&beacons_data);

                    // Initialize or get map state
                    if self.map_tiles.is_none() {
                        self.map_tiles = Some(HttpTiles::new(OpenStreetMap, ui.ctx().clone()));
                    }
                    if self.map_memory.is_none() {
                        self.map_memory = Some(MapMemory::default());
                    }

                    // Get mutable references to map state
                    let map_tiles = self.map_tiles.as_mut().unwrap();
                    let map_memory = self.map_memory.as_mut().unwrap();

                    // Add the map widget with plugin
                    ui.add(
                        Map::new(
                            Some(map_tiles),
                            map_memory,
                            Position::new(-122.4194, 37.7749), // San Francisco coordinates
                        )
                        .with_plugin(plugin),
                    );
                });
            });
    }
}
