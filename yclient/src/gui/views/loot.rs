use crate::gui::client::GuiClient;
use crate::models::Tab;
use base64::Engine as _;
use egui::{Color32, Ui, Vec2};
use egui_dock::DockState;
use egui_extras::{Column, TableBuilder};
use egui_phosphor::regular;
use image;

impl GuiClient {
    /// Render the loot view with a table of captured screenshots
    pub fn render_loot_view(&mut self, ui: &mut Ui) {
        // Collect screenshot data first to avoid borrow checker issues
        let screenshots_data: Vec<_> = self
            .screenshots
            .iter()
            .enumerate()
            .map(|(idx, (beacon_id, timestamp, data))| {
                (idx, beacon_id.clone(), timestamp.clone(), data.clone())
            })
            .collect();

        let mut screenshot_to_delete = None;

        // Create a frame for the screenshots table
        egui::Frame::none()
            .fill(ui.style().visuals.panel_fill)
            .outer_margin(1.0)
            .show(ui, |ui| {
                egui::ScrollArea::both().show(ui, |ui| {
                    ui.horizontal_wrapped(|ui| {
                        // Check if empty first
                        if screenshots_data.is_empty() {
                            ui.vertical_centered(|ui| {
                                ui.add_space(100.0);
                                ui.heading("No screenshots available yet");
                                ui.label("Screenshots you take will appear here");
                            });
                            return;
                        }

                        // Use reference in for loop to avoid moving screenshots_data
                        for (idx, beacon_id, timestamp, screenshot_data) in &screenshots_data {
                            ui.vertical(|ui| {
                                // Create a frame for each screenshot
                                egui::Frame::none()
                                    .fill(ui.style().visuals.window_fill)
                                    .stroke(ui.style().visuals.window_stroke)
                                    .rounding(4.0)
                                    .outer_margin(8.0)
                                    .inner_margin(8.0)
                                    .show(ui, |ui| {
                                        // Show the screenshot
                                        if let Ok(decoded) =
                                            base64::engine::general_purpose::STANDARD
                                                .decode(screenshot_data)
                                        {
                                            if let Ok(image) = image::load_from_memory(&decoded) {
                                                let size = [
                                                    image.width() as usize,
                                                    image.height() as usize,
                                                ];
                                                let pixels = image.to_rgba8().into_raw();
                                                let color_image =
                                                    egui::ColorImage::from_rgba_unmultiplied(
                                                        size, &pixels,
                                                    );
                                                let texture = ui.ctx().load_texture(
                                                    format!("screenshot_{}", idx),
                                                    color_image,
                                                    egui::TextureOptions::default(),
                                                );

                                                // Show a thumbnail (200x200 max)
                                                let aspect_ratio = size[0] as f32 / size[1] as f32;
                                                let max_size = 200.0;
                                                let display_size = if aspect_ratio > 1.0 {
                                                    Vec2::new(max_size, max_size / aspect_ratio)
                                                } else {
                                                    Vec2::new(max_size * aspect_ratio, max_size)
                                                };

                                                ui.image((texture.id(), display_size));
                                            }
                                        }

                                        // Show metadata and actions
                                        ui.vertical(|ui| {
                                            ui.label(format!("Beacon: {}", beacon_id));
                                            ui.label(format!("Taken: {}", timestamp));
                                            if ui
                                                .button(format!("{} Delete", regular::TRASH))
                                                .clicked()
                                            {
                                                screenshot_to_delete = Some(*idx);
                                            }
                                        });
                                    });
                            });
                        }
                    });
                });
            });

        // Handle deletion after the UI rendering
        if let Some(idx) = screenshot_to_delete {
            self.screenshots.remove(idx);
            self.request_repaint();
        }
    }
}
