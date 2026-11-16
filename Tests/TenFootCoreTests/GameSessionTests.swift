import Testing
@testable import TenFootCore

@Suite struct GameSessionTests {
    @Test func endsShortlyAfterTheGameQuits() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        #expect(!session.isOver(at: 60))
        session.processQuit(100, at: 60)
        #expect(!session.isOver(at: 61))
        #expect(session.isOver(at: 62))
    }

    @Test func otherAppsQuittingDontMatter() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        session.processQuit(999, at: 5)
        #expect(!session.isOver(at: 100))
    }

    @Test func followsAHandOffFromALauncherScript() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)                       // the script
        session.processQuit(100, at: 1)                 // it exits...
        let added = session.appLaunched(200, isWine: false, at: 2) // ...and the real app starts
        #expect(added)
        #expect(!session.isOver(at: 30))
        session.processQuit(200, at: 30)
        #expect(session.isOver(at: 32))
    }

    @Test func ignoresUnrelatedAppsOpenedLater() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        let added = session.appLaunched(300, isWine: false, at: 120) // e.g. Safari, mid-game
        #expect(!added)
        session.processQuit(100, at: 200)
        #expect(session.isOver(at: 202))
    }

    @Test func aHandOffTakesOnlyOneApp() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)                       // a Steam shortcut
        session.processQuit(100, at: 1)                 // hands off and quits
        let game = session.appLaunched(200, isWine: false, at: 3)
        let other = session.appLaunched(300, isWine: false, at: 4) // something else opening
        #expect(game)
        #expect(!other)
        #expect(session.processes == [200])
    }

    @Test func aGameQuittingAllowsAnotherHandOff() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        session.appLaunched(200, isWine: false, at: 1)  // launch slot used
        session.processQuit(200, at: 5)                 // e.g. a game restarting itself
        let again = session.appLaunched(201, isWine: false, at: 6)
        #expect(again)
    }

    @Test func anAppAlreadyTrackedDoesntUseTheHandOff() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        session.appLaunched(100, isWine: false, at: 0)  // the game's own launch notice
        let next = session.appLaunched(200, isWine: false, at: 1)
        #expect(next)
    }

    @Test func waitsForTheGameAfterAQuickHandOff() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)       // a Steam shortcut
        session.processQuit(100, at: 1) // quits at once; Steam is still starting
        #expect(!session.isOver(at: 5))
        let game = session.appLaunched(200, isWine: false, at: 8)
        #expect(game)
        session.processQuit(200, at: 600)
        #expect(session.isOver(at: 602)) // played, then quit: back as usual
    }

    @Test func givesUpOnAQuickHandOffThatGoesNowhere() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        session.processQuit(100, at: 1)
        #expect(!session.isOver(at: 10))
        #expect(session.isOver(at: 11))
    }

    @Test func closingDoesntWaitForAHandOff() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        session.closeRequested()
        session.processQuit(100, at: 1)
        #expect(session.isOver(at: 3))
    }

    @Test func takesNothingInOnceClosing() {
        var session = GameSession(expectsWine: true, at: 0)
        session.track(100, at: 0)
        session.closeRequested()
        session.processQuit(100, at: 1)
        let app = session.appLaunched(200, isWine: false, at: 2)
        let wine = session.appLaunched(300, isWine: true, at: 2)
        #expect(!app)
        #expect(!wine)
        #expect(session.processes.isEmpty)
    }

    @Test func aHandOffReopensOnlyWhenTheGameIsGone() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        session.track(101, at: 0)
        session.appLaunched(200, isWine: false, at: 1)  // launch slot used
        session.processQuit(101, at: 2)                 // one helper quits; 100 and 200 still run
        let other = session.appLaunched(300, isWine: false, at: 3)
        #expect(!other)
    }

    @Test func wineAppsOnlyJoinCrossOverGames() {
        var session = GameSession(expectsWine: false, at: 0)
        session.track(100, at: 0)
        session.appLaunched(200, isWine: false, at: 1)  // launch slot used
        let wine = session.appLaunched(400, isWine: true, at: 600) // e.g. another CrossOver bottle
        #expect(!wine)
    }

    @Test func neverTracksAllProcesses() {
        // -1 is what macOS reports for an app with no process; kill(-1) reaches every app.
        var session = GameSession(expectsWine: false, at: 0)
        session.track(-1, at: 0)
        session.track(0, at: 0)
        let wine = session.appLaunched(-1, isWine: true, at: 1)
        let handoff = session.appLaunched(0, isWine: false, at: 1)
        #expect(!wine)
        #expect(!handoff)
        #expect(session.processes.isEmpty)
    }

    @Test func waitsForWineAfterTheCrossOverLauncherQuits() {
        var session = GameSession(expectsWine: true, at: 0)
        session.track(100, at: 0)       // CrossOver launcher
        session.processQuit(100, at: 1) // quits before Wine shows up
        #expect(!session.isOver(at: 20))
        session.appLaunched(400, isWine: true, at: 20) // the Windows game
        session.processQuit(400, at: 300)
        #expect(!session.isOver(at: 301))
        #expect(session.isOver(at: 302))
    }

    @Test func wineAppsJoinAtAnyTime() {
        var session = GameSession(expectsWine: true, at: 0)
        session.track(100, at: 0)
        let added = session.appLaunched(500, isWine: true, at: 600)
        #expect(added)
        session.processQuit(100, at: 601)
        #expect(!session.isOver(at: 700))
    }

    @Test func givesUpIfNothingEverStarts() {
        let session = GameSession(expectsWine: false, at: 0)
        #expect(!session.isOver(at: 9))
        #expect(session.isOver(at: 10))
    }
}
