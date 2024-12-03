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

#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct Command {
    id: i64,
    beacon_id: String,
    command: String,
    status: String,
    created_at: String,
    result: Option<String>,
    completed_at: Option<String>,
}

#[derive(Debug, serde::Serialize)]
struct NewCommand {
    beacon_id: String,
    command: String,
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
        println!(
            "  {} - Send command to beacon",
            "run <beacon_id> <command>".cyan()
        );
        println!(
            "  {} - List commands for beacon",
            "commands <beacon_id>".cyan()
        );
        println!("  {} - Show this help message", "help".cyan());
        println!("  {} - Clear the screen", "clear".cyan());
        println!("  {} - Exit the client", "exit".cyan());
        println!();
    }

    fn handle_command(&self, command: &str) -> bool {
        let parts: Vec<&str> = command.trim().split_whitespace().collect();
        match parts.get(0).map(|s| *s) {
            Some("exit") | Some("quit") => {
                println!("{}", "Goodbye!".green());
                false
            }
            Some("help") => {
                self.print_help();
                true
            }
            Some("clear") => {
                print!("\x1B[2J\x1B[1;1H");
                true
            }
            Some("ping") => {
                self.send_ping();
                true
            }
            Some("beacons") => {
                self.list_beacons();
                true
            }
            Some("run") => {
                if parts.len() < 3 {
                    println!("{}", "Usage: run <beacon_id> <command>".red());
                } else {
                    let beacon_id = parts[1];
                    let command = parts[2..].join(" ");
                    self.send_command(beacon_id, &command);
                }
                true
            }
            Some("commands") => {
                if parts.len() != 2 {
                    println!("{}", "Usage: commands <beacon_id>".red());
                } else {
                    self.list_commands(parts[1]);
                }
                true
            }
            Some("") => true,
            Some(cmd) => {
                println!("{} {}", "Unknown command:".red(), cmd);
                true
            }
            None => true,
        }
    }

    fn send_command(&self, beacon_id: &str, command: &str) {
        let new_command = NewCommand {
            beacon_id: beacon_id.to_string(),
            command: command.to_string(),
        };

        match reqwest::blocking::Client::new()
            .post(format!("{}/command/new", self.server_url))
            .json(&new_command)
            .send()
        {
            Ok(response) => {
                if response.status().is_success() {
                    match response.json::<Command>() {
                        Ok(cmd) => {
                            println!(
                                "{} Command {} scheduled for beacon {}",
                                "Success:".green(),
                                cmd.id.to_string().yellow(),
                                cmd.beacon_id.cyan()
                            );
                        }
                        Err(e) => println!("{} {}", "Failed to parse response:".red(), e),
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
            Err(e) => println!("{} {}", "Failed to send command:".red(), e),
        }
    }

    fn list_commands(&self, beacon_id: &str) {
        match reqwest::blocking::get(format!("{}/command/list/{}", self.server_url, beacon_id)) {
            Ok(response) => {
                if response.status().is_success() {
                    match response.json::<Vec<Command>>() {
                        Ok(commands) => {
                            if commands.is_empty() {
                                println!(
                                    "\n{} No commands found for beacon {}",
                                    "Info:".blue(),
                                    beacon_id
                                );
                            } else {
                                println!(
                                    "\n{} for beacon {}:",
                                    "Commands".green().bold(),
                                    beacon_id.cyan()
                                );
                                println!("{:-<80}", "");
                                for cmd in commands {
                                    println!(
                                        "ID: {} | Status: {} | Created: {}",
                                        cmd.id.to_string().yellow(),
                                        cmd.status.green(),
                                        cmd.created_at.blue()
                                    );
                                    println!("Command: {}", cmd.command);
                                    if let Some(result) = cmd.result {
                                        println!("Result: {}", result.green());
                                    }
                                    if let Some(completed_at) = cmd.completed_at {
                                        println!("Completed: {}", completed_at.blue());
                                    }
                                    println!("{:-<80}", "");
                                }
                            }
                            println!();
                        }
                        Err(e) => println!("{} {}", "Failed to parse commands:".red(), e),
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
            Err(e) => println!("{} {}", "Failed to fetch commands:".red(), e),
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
