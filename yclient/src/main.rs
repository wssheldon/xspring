use clap::Parser;
use std::process;

// Import modules
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
        match Client::new() {
            Ok(mut client) => {
                if let Err(e) = client.run() {
                    eprintln!("Error: {}", e);
                    process::exit(1);
                }
                Ok(())
            }
            Err(e) => {
                eprintln!("Failed to initialize client: {}", e);
                process::exit(1);
            }
        }
    } else {
        // Run in GUI mode (default)
        let options = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default()
                .with_inner_size([1280.0, 720.0])
                .with_min_inner_size([800.0, 600.0]),
            ..Default::default()
        };

        // Start the GUI application
        eframe::run_native(
            "XClient",
            options,
            Box::new(|cc| Ok(Box::new(GuiClient::new(cc)))),
        )
    }
}
