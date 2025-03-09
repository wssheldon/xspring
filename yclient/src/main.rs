use clap::Parser;
use std::process;

// Import modules
mod api;
mod cli;
mod gui;
mod models;
mod utils;

// Re-export main types for easier access
use cli::Client;
use gui::GuiClient;

// Define CLI args using clap derive feature
#[derive(Parser)]
#[command(
    name = "XClient",
    about = "Command and control client",
    version = "0.1.0"
)]
struct Args {
    /// Run in CLI mode instead of GUI
    #[arg(long)]
    cli: bool,
}

fn main() -> Result<(), eframe::Error> {
    // Parse command line arguments
    let args = Args::parse();

    // Run in CLI mode if --cli flag is provided
    if args.cli {
        // Create a new runtime for CLI mode
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            match Client::new() {
                Ok(mut client) => {
                    if let Err(e) = client.run().await {
                        eprintln!("Error: {}", e);
                        process::exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("Failed to initialize client: {}", e);
                    process::exit(1);
                }
            }
        });
        Ok(())
    } else {
        // Run GUI mode
        let options = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default()
                .with_inner_size([1920.0, 1080.0]) // Default 960x540 * 2
                .with_min_inner_size([800.0, 600.0])
                .with_decorations(true)
                .with_transparent(true)
                .with_title_shown(true)
                .with_titlebar_shown(true)
                .with_titlebar_buttons_shown(true)
                .with_title("🌸💐"),
            vsync: true,
            multisampling: 0,
            depth_buffer: 0,
            stencil_buffer: 0,
            ..Default::default()
        };

        eframe::run_native(
            "🌸💐",
            options,
            Box::new(|cc| {
                // Configure dark visuals
                let mut visuals = egui::Visuals::dark();
                visuals.panel_fill = egui::Color32::from_rgb(20, 20, 20);
                visuals.window_fill = egui::Color32::from_rgb(20, 20, 20);
                visuals.override_text_color = Some(egui::Color32::WHITE);
                cc.egui_ctx.set_visuals(visuals);
                Ok(Box::new(GuiClient::new(cc)))
            }),
        )
    }
}
