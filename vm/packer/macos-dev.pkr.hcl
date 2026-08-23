packer {
  required_plugins {
    tart = {
      version = ">= 1.14.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "base_image" {
  type        = string
  default     = "ghcr.io/cirruslabs/macos-tahoe-xcode:latest"
  description = "Base macOS image with full Xcode (required for #Preview macro compilation)"
}

variable "vm_name" {
  type        = string
  default     = "macos-dev"
  description = "Name for the built VM. Deliberately not project-specific: one VM is shared across projects, each syncing to its own ~/Projects/<name>."
}

variable "cpu_count" {
  type    = number
  default = 4
}

variable "memory_gb" {
  type    = number
  default = 8
}

variable "disk_size_gb" {
  type    = number
  default = 150
}

variable "ssh_username" {
  type    = string
  default = "admin"
}

variable "ssh_password" {
  type      = string
  default   = "admin"
  sensitive = true
}

source "tart-cli" "windowthing" {
  vm_base_name = var.base_image
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = var.disk_size_gb
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "1200s"

  headless = true
}

build {
  sources = ["source.tart-cli.windowthing"]

  # Disable Spotlight indexing for faster builds
  provisioner "shell" {
    inline = [
      "echo 'Disabling Spotlight indexing...'",
      "sudo mdutil -a -i off || true"
    ]
  }

  # Disable sleep and screen saver
  provisioner "shell" {
    inline = [
      "echo 'Disabling sleep and screen saver...'",
      "sudo pmset -a sleep 0",
      "sudo pmset -a displaysleep 0",
      "sudo pmset -a disksleep 0",
      "defaults write com.apple.screensaver idleTime 0"
    ]
  }

  # Install Homebrew if not present
  provisioner "shell" {
    inline = [
      "echo 'Checking Homebrew...'",
      "if ! command -v brew &> /dev/null; then",
      "  echo 'Installing Homebrew...'",
      "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
      "  echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile",
      "  eval \"$(/opt/homebrew/bin/brew shellenv)\"",
      "fi"
    ]
  }

  # Copy setup script
  provisioner "file" {
    source      = "scripts/setup.sh"
    destination = "~/setup.sh"
  }

  # Run setup script
  provisioner "shell" {
    inline = [
      "chmod +x ~/setup.sh",
      "~/setup.sh"
    ]
  }

  # Clean up for smaller image
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "eval \"$(/opt/homebrew/bin/brew shellenv)\"",
      "brew cleanup -s || true",
      "rm -rf ~/Library/Caches/* || true",
      "rm -rf /tmp/* || true"
    ]
  }
}
