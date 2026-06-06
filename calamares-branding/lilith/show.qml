/* =========================================================
   Calamares Installation Slideshow — Lilith Linux
   QML slideshow shown during the install process
   ========================================================= */
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    // Auto-advance timer
    Timer {
        id: slideTimer
        interval: 5000
        repeat: true
        running: presentation.activatedInCalamares
        onTriggered: presentation.goToNextSlide()
    }

    // ==========================================================
    // Slide 1 — Welcome to Lilith Linux
    // ==========================================================
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0D0D0D"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 24

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: "banner.png"
                    width: 400
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Welcome to Lilith Linux"
                    font.pixelSize: 32
                    font.bold: true
                    color: "#FFFFFF"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Ubuntu 26.04 (Resolute) · COSMIC Desktop"
                    font.pixelSize: 16
                    color: "#888888"
                    font.letterSpacing: 1
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 120
                    height: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#C0392B" }
                        GradientStop { position: 0.5; color: "#FF6B35" }
                        GradientStop { position: 1.0; color: "#C0392B" }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 500
                    text: "Your system is being configured.\nSit back while we set everything up for you."
                    font.pixelSize: 14
                    color: "#BBBBBB"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ==========================================================
    // Slide 2 — COSMIC Desktop
    // ==========================================================
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0D0D0D"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                width: 600

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "🔥"
                    font.pixelSize: 60
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "COSMIC Desktop"
                    font.pixelSize: 28
                    font.bold: true
                    color: "#FFFFFF"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 500
                    text: "Powered by System76's COSMIC desktop environment — built with Rust for speed, stability, and a beautiful Wayland-native experience."
                    font.pixelSize: 14
                    color: "#BBBBBB"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ==========================================================
    // Slide 3 — Custom Applications
    // ==========================================================
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0D0D0D"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                width: 600

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "⚡"
                    font.pixelSize: 60
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Built-In Power Tools"
                    font.pixelSize: 28
                    font.bold: true
                    color: "#FFFFFF"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 500
                    text: "Offerings · Tweakers · Ouija-Pad · Stake · Lilim AI\nHellFire Browser · Hyper Terminal · and more"
                    font.pixelSize: 14
                    color: "#BBBBBB"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ==========================================================
    // Slide 4 — Rust-Powered Core
    // ==========================================================
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0D0D0D"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                width: 600

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "🦀"
                    font.pixelSize: 60
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Rust-Powered CLI"
                    font.pixelSize: 28
                    font.bold: true
                    color: "#FFFFFF"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 500
                    text: "Nushell · lsd · bat · ripgrep · fd · atuin · starship\nzoxide · topgrade · procs · and more modern Rust tools pre-installed."
                    font.pixelSize: 14
                    color: "#BBBBBB"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ==========================================================
    // Slide 5 — Almost Done
    // ==========================================================
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0D0D0D"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 24

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: "logo.png"
                    width: 120
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Almost There..."
                    font.pixelSize: 28
                    font.bold: true
                    color: "#FFFFFF"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 500
                    text: "Lilith Linux is being installed.\nYour new system will be ready shortly."
                    font.pixelSize: 14
                    color: "#BBBBBB"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
