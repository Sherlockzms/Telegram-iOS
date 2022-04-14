import Foundation
import Postbox
import TelegramApi

extension BotMenuButton {
    init(apiBotMenuButton: Api.BotMenuButton) {
        switch apiBotMenuButton {
            case .botMenuButtonCommands, .botMenuButtonDefault:
                self = .commands
            case let .botMenuButton(text, url):
                self = .webView(text: text, url: url)
        }
    }
}

extension BotInfo {
    convenience init(apiBotInfo: Api.BotInfo) {
        switch apiBotInfo {
            case let .botInfo(_, _, description, _, apiCommands, apiMenuButton):
                var commands: [BotCommand] = []
                if let apiCommands = apiCommands {
                    commands = apiCommands.map { command in
                        switch command {
                            case let .botCommand(command, description):
                                return BotCommand(text: command, description: description)
                        }
                    }
                }
                var menuButton: BotMenuButton = .commands
                if let apiMenuButton = apiMenuButton {
                    menuButton = BotMenuButton(apiBotMenuButton: apiMenuButton)
                }
                self.init(description: description ?? "", commands: commands, menuButton: menuButton)
        }
    }
}
