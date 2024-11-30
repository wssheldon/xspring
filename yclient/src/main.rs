use colored::*;
use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};
use std::path::PathBuf;

struct Client {
    editor: DefaultEditor,
    history_path: PathBuf,
    server_url: String,
}

#[derive(serde::Deserialize, Debug)]
struct Beacon {
    id: String,
    last_seen: String,
    status: String,
    hostname: Option<String>,
    username: Option<String>,
    os_version: Option<String>,
}

impl Client {
    fn new() -> Result<Self> {
        let mut editor = DefaultEditor::new()?;
        let history_path = dirs::home_dir()
            .unwrap_or_default()
            .join(".xclient_history");

        // Load history if it exists
        if editor.load_history(&history_path).is_err() {
            println!("{}", "No previous history.".yellow());
        }

        Ok(Self {
            editor,
            history_path,
            server_url: String::from("http://127.0.0.1:4444"),
        })
    }

    fn print_help(&self) {
        println!("\n{}", "Available Commands:".green().bold());
        println!("  {} - Send ping to server", "ping".cyan());
        println!("  {} - List active beacons", "beacons".cyan());
        println!("  {} - Show this help message", "help".cyan());
        println!("  {} - Clear the screen", "clear".cyan());
        println!("  {} - Exit the client", "exit".cyan());
        println!();
    }

    fn handle_command(&self, command: &str) -> bool {
        match command.trim() {
            "exit" | "quit" => {
                println!("{}", "Goodbye!".green());
                false
            }
            "help" => {
                self.print_help();
                true
            }
            "clear" => {
                print!("\x1B[2J\x1B[1;1H");
                true
            }
            "ping" => {
                self.send_ping();
                true
            }
            "beacons" => {
                self.list_beacons();
                true
            }
            "" => true,
            cmd => {
                println!("{} {}", "Unknown command:".red(), cmd);
                true
            }
        }
    }

    fn send_ping(&self) {
        match reqwest::blocking::Client::new()
            .post(&self.server_url)
            .body(format!("PING client"))
            .send()
        {
            Ok(response) => {
                if response.status().is_success() {
                    match response.text() {
                        Ok(text) => println!("{} {}", "Server response:".green(), text),
                        Err(e) => println!("{} {}", "Failed to read response:".red(), e),
                    }
                } else {
                    println!(
                        "{} {} ({})",
                        "Server error:".red(),
                        response.status(),
                        response.status().as_str()
                    );
                }
            }
            Err(e) => println!("{} {}", "Failed to send request:".red(), e),
        }
    }

    fn run(&mut self) -> Result<()> {
        println!("{}", "\nWelcome to XClient!".green().bold());
        self.print_help();

        loop {
            let prompt = format!("{} ", ">>".cyan().bold());
            match self.editor.readline(&prompt) {
                Ok(line) => {
                    self.editor.add_history_entry(line.as_str())?;
                    if !self.handle_command(&line) {
                        break;
                    }
                }
                Err(ReadlineError::Interrupted) => {
                    println!("{}", "CTRL-C".yellow());
                    break;
                }
                Err(ReadlineError::Eof) => {
                    println!("{}", "CTRL-D".yellow());
                    break;
                }
                Err(err) => {
                    println!("{} {:?}", "Error:".red(), err);
                    break;
                }
            }
        }

        // Save history
        if let Err(e) = self.editor.save_history(&self.history_path) {
            println!("{} {}", "Failed to save history:".red(), e);
        }

        Ok(())
    }
    fn list_beacons(&self) {
        match reqwest::blocking::get(format!("{}/beacons", self.server_url)) {
            Ok(response) => {
                if response.status().is_success() {
                    match response.json::<Vec<Beacon>>() {
                        Ok(beacons) => {
                            println!("\n{}", "Active Beacons:".green().bold());
                            println!("{:-<80}", "");
                            for beacon in beacons {
                                println!(
                                    "{}: {} ({})",
                                    beacon.id.cyan(),
                                    beacon.last_seen.yellow(),
                                    beacon.status.green()
                                );
                                if let Some(hostname) = beacon.hostname {
                                    println!("  Hostname: {}", hostname.blue());
                                }
                                if let Some(username) = beacon.username {
                                    println!("  User: {}", username.blue());
                                }
                                if let Some(os_version) = beacon.os_version {
                                    println!("  OS: {}", os_version.blue());
                                }
                                println!("{:-<80}", "");
                            }
                            println!();
                        }
                        Err(e) => println!("{} {}", "Failed to parse beacons:".red(), e),
                    }
                } else {
                    println!(
                        "{} {} ({})",
                        "Server error:".red(),
                        response.status(),
                        response.status().as_str()
                    );
                }
            }
            Err(e) => println!("{} {}", "Failed to fetch beacons:".red(), e),
        }
    }
}

fn main() -> Result<()> {
    let mut client = Client::new()?;
    client.run()
}
