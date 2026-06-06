// Lilith Linux SDDM Theme — Main QML File
// Dark flame aesthetic: black background, crimson/orange accents
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080

    // ── Background ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#0D0D0D"  // Deep black
    }

    // Subtle flame gradient overlay at bottom
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.35
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#1A0A0A" }  // Very dark red tint
        }
    }

    // Background image (wallpaper)
    Image {
        id: bgImage
        anchors.fill: parent
        source: "background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.25  // Subtle background - keeps dark flame feel
    }

    // ── Lilith Banner Logo ────────────────────────────────────────────────────
    Image {
        id: banner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.08
        source: "banner.png"
        width: Math.min(parent.width * 0.4, 600)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    // Tagline
    Text {
        anchors.top: banner.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Lilith Linux"
        font.pixelSize: 14
        font.letterSpacing: 4
        color: "#8B3A3A"
        font.family: "sans-serif"
    }

    // ── Login Card ────────────────────────────────────────────────────────────
    Rectangle {
        id: loginCard
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 40
        width: 420
        height: 340
        radius: 16
        color: "#111111"
        border.color: "#2A1010"
        border.width: 1

        // Glow effect
        layer.enabled: true
        layer.effect: null

        // Thin flame accent line at top
        Rectangle {
            width: parent.width
            height: 2
            radius: 2
            anchors.top: parent.top
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#C0392B" }
                GradientStop { position: 0.5; color: "#FF6B35" }
                GradientStop { position: 1.0; color: "#C0392B" }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 20

            // Username field
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "USERNAME"
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: "#666666"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 8
                    color: "#1A1A1A"
                    border.color: usernameInput.activeFocus ? "#E74C3C" : "#2A2A2A"
                    border.width: 1

                    TextInput {
                        id: usernameInput
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 14
                        color: "#FFFFFF"
                        text: userModel.lastUser
                        KeyNavigation.tab: passwordInput
                        Keys.onReturnPressed: passwordInput.forceActiveFocus()

                        // Placeholder
                        Text {
                            visible: parent.text.length === 0
                            text: "Enter username"
                            color: "#444444"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Password field
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "PASSWORD"
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: "#666666"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 8
                    color: "#1A1A1A"
                    border.color: passwordInput.activeFocus ? "#E74C3C" : "#2A2A2A"
                    border.width: 1

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 14
                        color: "#FFFFFF"
                        echoMode: TextInput.Password
                        passwordMaskDelay: 800
                        KeyNavigation.tab: sessionCombo
                        Keys.onReturnPressed: sddm.login(usernameInput.text, passwordInput.text, sessionCombo.currentIndex)

                        Text {
                            visible: parent.text.length === 0
                            text: "Enter password"
                            color: "#444444"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Session selector
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "SESSION"
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: "#666666"
                }

                ComboBox {
                    id: sessionCombo
                    Layout.fillWidth: true
                    height: 44
                    model: sessionModel
                    currentIndex: sessionModel.lastIndex

                    contentItem: Text {
                        leftPadding: 12
                        text: sessionCombo.currentText
                        color: "#CCCCCC"
                        font.pixelSize: 14
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: 8
                        color: "#1A1A1A"
                        border.color: sessionCombo.activeFocus ? "#E74C3C" : "#2A2A2A"
                        border.width: 1
                    }

                    delegate: ItemDelegate {
                        width: sessionCombo.width
                        contentItem: Text {
                            text: modelData.name || model.name
                            color: "#CCCCCC"
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: highlighted ? "#2A0A0A" : "#1A1A1A"
                        }
                    }

                    popup: Popup {
                        y: sessionCombo.height + 4
                        width: sessionCombo.width
                        background: Rectangle {
                            color: "#1A1A1A"
                            border.color: "#2A2A2A"
                            radius: 8
                        }
                        contentItem: ListView {
                            model: sessionCombo.delegateModel
                            currentIndex: sessionCombo.highlightedIndex
                            clip: true
                        }
                    }
                }
            }

            // Login button
            Button {
                id: loginBtn
                Layout.fillWidth: true
                height: 44
                text: "SIGN IN"

                contentItem: Text {
                    text: loginBtn.text
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: loginBtn.pressed ? "#8B1A1A" : "#C0392B" }
                        GradientStop { position: 0.5; color: loginBtn.pressed ? "#A02020" : "#E74C3C" }
                        GradientStop { position: 1.0; color: loginBtn.pressed ? "#8B1A1A" : "#C0392B" }
                    }
                }

                onClicked: sddm.login(usernameInput.text, passwordInput.text, sessionCombo.currentIndex)
            }
        }
    }

    // ── Bottom bar ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: 24
        anchors.leftMargin: 40
        anchors.rightMargin: 40

        // Clock
        Text {
            id: clock
            font.pixelSize: 28
            color: "#FFFFFF"
            opacity: 0.8

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm")
            }
            Component.onCompleted: clock.text = Qt.formatTime(new Date(), "hh:mm")
        }

        Text {
            font.pixelSize: 13
            color: "#666666"
            text: Qt.formatDate(new Date(), "dddd, MMMM d")
            Layout.leftMargin: 12
        }

        Item { Layout.fillWidth: true }

        // Power buttons
        RowLayout {
            spacing: 16

            // Reboot
            Button {
                text: "↺"
                width: 44
                height: 44
                font.pixelSize: 20
                onClicked: sddm.reboot()
                contentItem: Text {
                    text: parent.text; color: "#888888"; font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { color: "transparent" }
                ToolTip { text: "Reboot"; delay: 500 }
            }

            // Shutdown
            Button {
                text: "⏻"
                width: 44
                height: 44
                font.pixelSize: 20
                onClicked: sddm.powerOff()
                contentItem: Text {
                    text: parent.text; color: "#888888"; font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { color: "transparent" }
                ToolTip { text: "Shut Down"; delay: 500 }
            }
        }
    }

    // ── Error message ─────────────────────────────────────────────────────────
    Connections {
        target: sddm

        function onLoginFailed() {
            errorMsg.visible = true
            passwordInput.text = ""
            passwordInput.forceActiveFocus()
        }
    }

    Rectangle {
        id: errorMsg
        visible: false
        anchors.top: loginCard.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: loginCard.width
        height: 36
        radius: 8
        color: "#2A0A0A"
        border.color: "#C0392B"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "Incorrect username or password"
            color: "#E74C3C"
            font.pixelSize: 13
        }
    }

    Component.onCompleted: {
        if (usernameInput.text === "")
            usernameInput.forceActiveFocus()
        else
            passwordInput.forceActiveFocus()
    }
}
