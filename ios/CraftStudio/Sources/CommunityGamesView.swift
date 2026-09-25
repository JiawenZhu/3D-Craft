import SwiftUI
import SafariServices

enum CommunityCategory: String, CaseIterable, Identifiable {
    case fun, animation, visuals, creativity
    var id: String { rawValue }
    func title(_ chinese: Bool) -> String {
        switch self {
        case .fun: return chinese ? "最好玩" : "Most fun"
        case .animation: return chinese ? "最佳动画" : "Best animation"
        case .visuals: return chinese ? "最佳视觉" : "Best visuals"
        case .creativity: return chinese ? "最有创意" : "Most creative"
        }
    }
    var symbol: String {
        switch self { case .fun: return "gamecontroller"; case .animation: return "figure.dance"; case .visuals: return "sparkles"; case .creativity: return "lightbulb" }
    }
}
struct CommunityGame: Identifiable {
    let id: String, title: String, creator: String, description: String, link: String, coverLink: String
    var votes: [String:Int], myVotes: [String]
    let isMine: Bool, reachable: Bool
    let moderationStatus: String, reviewNote: String
    init(_ d: [String:Any]) {
        id=d["id"] as? String ?? ""; title=d["title"] as? String ?? ""; creator=d["creator"] as? String ?? ""
        description=d["description"] as? String ?? "";link=d["url"] as? String ?? ""
        coverLink=d["coverUrl"] as? String ?? ""
        votes=d["votes"] as? [String:Int] ?? [:];myVotes=d["myVotes"] as? [String] ?? []
        isMine=d["isMine"] as? Bool ?? false;reachable=d["reachable"] as? Bool ?? false
        moderationStatus=d["moderationStatus"] as? String ?? "pending"
        reviewNote=d["reviewNote"] as? String ?? ""
    }
}
struct CommunityBrowser: Identifiable { let id=UUID(); let url: URL }
struct GameBrowserView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url:url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct CommunityGamesView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var account = CraftAccount.shared
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @State private var category: CommunityCategory = .fun
    @State private var games: [CommunityGame] = []
    @State private var mine = false
    @State private var hasMore = false
    @State private var loading = false
    @State private var busy = Set<String>()
    @State private var error: String?
    @State private var submitting = false
    @State private var signIn = false
    @State private var browser: CommunityBrowser?
    @State private var reporting: CommunityGame?
    @State private var reportReason = ""
    @State private var removing: CommunityGame?
    @State private var blocking: CommunityGame?
    @State private var managingBlocks = false
    @State private var nextOffset = 0
    @State private var notice: String?
    @State private var requestID = UUID()
    @State private var votePulse = 0
    @State private var loadedScope = ""
    @State private var openCompletionAfterGame = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(store.t("Community games", "社区游戏"), systemImage: "trophy.fill").font(.title2.bold())
                    Spacer()
                    Button { if account.uid == nil { signIn=true } else { submitting=true } } label: { Image(systemName:"plus").frame(width:44,height:44).background(appearance.washStrong,in:Circle()) }
                        .accessibilityLabel(store.t("Share a game", "发布游戏")).accessibilityIdentifier("community.submit")
                }
                if let job = store.jobs.first(where: { $0.kind == "model" && $0.isActive }) {
                    PlayWhileCreatingCard(job: job, inGames: true)
                }
                Text(store.t("Small worlds. Big adventures.", "小小世界，大大冒险。"))
                    .font(.largeTitle.bold()).fixedSize(horizontal:false,vertical:true)
                Text(store.t("Play each other’s games and vote for your favorites. One like per game in each category; tap again to undo.", "玩玩彼此的游戏，为喜欢的作品投票。每人可在每个类别为游戏点一次赞，再点即可撤回。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                if !mine && !games.isEmpty { featuredGames }
                HStack {
                    Text(mine ? store.t("Your games", "你的游戏") : store.t("Player favorites", "玩家精选")).font(.title3.bold())
                    Spacer()
                    Text("\(games.count) " + store.t("games", "款游戏")).font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) {
                        ForEach(CommunityCategory.allCases) { value in
                            Button { withAnimation(CraftMotion.gated(.snap, reduceMotion)) { mine=false;category=value } } label: { Label(value.title(store.isChinese),systemImage:value.symbol).font(.subheadline.weight(.semibold)).padding(.horizontal,14).frame(minHeight:44).foregroundStyle(!mine && value==category ? appearance.buttonInk : appearance.ink).background(!mine && value==category ? appearance.fill : CraftTheme.card,in:Capsule()) }
                                .accessibilityIdentifier("community.category."+value.rawValue)
                                .accessibilityAddTraits(!mine && value==category ? .isSelected : [])
                        }
                    }
                }
                if account.uid != nil {
                    Button { mine.toggle() } label: { Label(mine ? store.t("Back to rankings", "返回排行榜") : store.t("My submissions", "我发布的游戏"), systemImage:"person.crop.rectangle") }
                        .accessibilityIdentifier("community.mine")
                    Button { managingBlocks=true } label: { Label(store.t("Blocked creators", "已屏蔽的创作者"), systemImage:"person.slash") }
                }
                if let notice { Text(notice).font(.callout).foregroundStyle(appearance.ink) }
                if let error { VStack(alignment:.leading,spacing:8) { Text(error).foregroundStyle(.red);Button(store.t("Retry", "重试")) { Task { await load() } } }.font(.callout) }
                if loading && games.isEmpty { ProgressView(store.t("Loading games…", "正在加载游戏……")).frame(maxWidth:.infinity).padding(30) }
                else if games.isEmpty && error == nil {
                    ContentUnavailableView(store.t("The next game could be yours", "下一个游戏，可以是你的"),systemImage:"gamecontroller",description:Text(store.t("Share a published browser game to join the community. Rankings start with real player votes.", "发布浏览器游戏，加入社区。排行榜从真实玩家的投票开始。")))
                }
                ForEach(Array(games.enumerated()),id:\.element.id) { index, game in gameCard(game,rank:index+1) }
                if hasMore { Button(store.t("Load more", "加载更多")) { Task { await load(more:true) } }.disabled(loading) }
                Text(store.t("Games open on their creators’ websites. Use the game menu to report content or block a creator.", "游戏会在创作者的网站中打开。可通过游戏菜单举报内容或屏蔽创作者。"))
                    .font(.caption).foregroundStyle(.secondary)
                Link(store.t("Community support", "社区支持"), destination: URL(string:"https://3d-craft.web.app/contact")!)
            }.padding(22).frame(maxWidth:700).frame(maxWidth:.infinity)
        }
        .background(StudioAtmosphere()).tint(appearance.ink)
        .refreshable { await load() }
        .task(id: "\(category.rawValue)-\(mine)-\(account.uid ?? "guest")") { await load() }
        .onDisappear { requestID=UUID() }
        .sheet(isPresented:$submitting) { CommunitySubmissionView { notice=store.t("Submitted for review. See My submissions for its status.", "已提交审核，可在我发布的游戏中查看状态。");mine=true;Task { await load() } } }
        .sheet(isPresented:$managingBlocks) { CommunityBlocksView { Task { await load() } } }
        .sheet(isPresented:$signIn) { CraftSignInView() }
        .sheet(item:$browser, onDismiss: {
            if openCompletionAfterGame { openCompletionAfterGame=false; store.openCompletedModel() }
        }) { game in
            GameBrowserView(url:game.url).ignoresSafeArea()
                .safeAreaInset(edge: .bottom) {
                    CreationReadyCard { openCompletionAfterGame=true; browser=nil }
                }
        }
        .craftFeedback(.favoriteOn, trigger: votePulse)
        .alert(store.t("Report game", "举报游戏"),isPresented:Binding(get:{reporting != nil},set:{if !$0 { reporting=nil }})) {
            TextField(store.t("Reason", "原因"),text:$reportReason)
            Button(store.t("Report & hide", "举报并隐藏")) { if let game=reporting { let reason=reportReason;perform(game) { _=try await store.communityRequest("/games/\(game.id)/report",method:"POST",body:["reason":reason]);await load();notice=store.t("Report saved. This game is now hidden from your community.", "举报已保存，此游戏已从你的社区中隐藏。") } } }.disabled(reportReason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            Button(store.t("Cancel", "取消"),role:.cancel) { reporting=nil }
        } message: { Text(store.t("This hides the game from your rankings and saves your report for review.", "将从你的排行榜隐藏此游戏，并保存举报供审核。")) }
        .confirmationDialog(store.t("Block this creator?", "屏蔽此创作者？"),isPresented:Binding(get:{blocking != nil},set:{if !$0 {blocking=nil}})) {
            Button(store.t("Block creator", "屏蔽创作者"),role:.destructive) { if let game=blocking { perform(game) { _=try await store.communityRequest("/games/\(game.id)/block",method:"POST");await load();notice=store.t("Creator blocked. Their games are hidden on this account.", "已屏蔽创作者，其游戏将不会在此账号中显示。") } } }
        } message: { Text(store.t("Hide all games from this creator. You can undo this in Blocked creators.", "隐藏此创作者的所有游戏。可在已屏蔽的创作者中取消。")) }
        .confirmationDialog(store.t("Remove your game from the community?", "将你的游戏从社区下架？"),isPresented:Binding(get:{removing != nil},set:{if !$0 {removing=nil}})) {
            Button(store.t("Remove game", "下架游戏"),role:.destructive) { if let game=removing { perform(game) { _=try await store.communityRequest("/games/\(game.id)",method:"DELETE"); await load() } } }
        }
    }
    private func gameCard(_ game: CommunityGame, rank: Int) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Button { play(game) } label: {
                gameArtwork(game, symbol: category.symbol)
                    .overlay(alignment: .bottomTrailing) {
                        Label(store.t("Jump in", "开始玩"), systemImage: "play.fill")
                            .font(.caption.bold()).padding(10).background(.regularMaterial,in:Capsule()).padding(12)
                    }
            }.buttonStyle(CraftPressStyle()).disabled(game.moderationStatus != "approved" || !game.reachable).accessibilityLabel(store.t("Play ", "玩 ")+game.title)
            HStack(alignment:.top,spacing:12) {
                Text(mine ? "🎮" : "\(rank)").font(.title2.bold()).frame(width:48,height:48).background(appearance.washStrong,in:RoundedRectangle(cornerRadius:14))
                VStack(alignment:.leading,spacing:4) {
                    Text(game.title).font(.title3.bold())
                    Text(game.creator).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Menu {
                    if let url = URL(string: game.link) {
                        Button {
                            UIPasteboard.general.string = game.link
                        } label: {
                            Label(store.t("Copy full link", "复制完整链接"), systemImage: "doc.on.doc")
                        }
                        ShareLink(item: url) {
                            Label(store.t("Share game link", "分享游戏链接"), systemImage: "square.and.arrow.up")
                        }
                        Button {
                            play(game)
                        } label: {
                            Label(store.t("Open game", "打开游戏"), systemImage: "safari")
                        }
                    }
                    if game.isMine {
                        Button(store.t("Check link again", "重新检查链接")) { perform(game) { _=try await store.communityRequest("/games/\(game.id)/recheck",method:"POST");await load() } }
                        Button(store.t("Remove game", "下架游戏"),role:.destructive) { removing=game }
                    }
                    if game.moderationStatus == "approved" {
                        Button(store.t("Report game", "举报游戏")) { if account.uid == nil {signIn=true} else {reportReason="";reporting=game} }
                        if !game.isMine { Button(store.t("Block creator", "屏蔽创作者"),role:.destructive) { if account.uid == nil {signIn=true} else {blocking=game} } }
                    }
                } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel(store.t("Game options", "游戏选项"))
            }
            if !game.description.isEmpty { Text(game.description).font(.subheadline) }
            if let host = URL(string: game.link)?.host {
                Label(host, systemImage: "globe").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if game.moderationStatus != "approved" {
                Label(game.moderationStatus == "rejected" ? store.t("Not approved", "未通过审核") : store.t("Awaiting review", "等待审核"),systemImage:"clock").font(.subheadline).foregroundStyle(.secondary)
                if !game.reviewNote.isEmpty { Text(game.reviewNote).font(.caption) }
            }
            if !game.reachable { Text(store.t("Link unavailable. Check your published page and try again.", "链接暂不可用，请检查已发布的页面后重试。")).font(.caption).foregroundStyle(.orange) }
            HStack(spacing:12) {
                Button { play(game)
                } label: {
                    Label(store.t("Play game", "玩游戏"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(appearance.washStrong, in: Capsule())
                }
                .accessibilityIdentifier("community.play."+game.id)
                .disabled(game.moderationStatus != "approved" || !game.reachable)
                Button { vote(game) } label: {
                    HStack(spacing: 7) {
                        Image(systemName:game.myVotes.contains(category.rawValue) ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .symbolEffect(.bounce, value: reduceMotion ? false : game.myVotes.contains(category.rawValue))
                        Text("\(game.votes[category.rawValue] ?? 0)")
                            .contentTransition(.numericText())
                    }.font(.subheadline.bold()).padding(.horizontal,18).frame(minHeight:46)
                        .foregroundStyle(game.myVotes.contains(category.rawValue) ? appearance.buttonInk : appearance.ink)
                        .background(game.myVotes.contains(category.rawValue) ? appearance.fill : appearance.washSoft,in:Capsule())
                }
                .buttonStyle(CraftPressStyle())
                .disabled(busy.contains(game.id) || game.moderationStatus != "approved")
                .accessibilityLabel(category.title(store.isChinese)+", \(game.votes[category.rawValue] ?? 0) "+store.t("likes", "赞"))
                .accessibilityValue(game.myVotes.contains(category.rawValue) ? store.t("Liked", "已点赞") : store.t("Not liked", "未点赞"))
                .accessibilityIdentifier("community.vote."+game.id)
            }
            if busy.contains(game.id) {
                Label(store.t("Updating…", "正在更新……"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2).foregroundStyle(.secondary)
            }

        }.craftPanel()
    }
    private var featuredGames: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(games.prefix(5))) { game in
                    Button { play(game) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            gameArtwork(game, symbol: "gamecontroller.fill")
                            Text(game.title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .topLeading)
                            Label(store.t("Play now", "马上开玩"), systemImage: "play.circle.fill").font(.subheadline.bold())
                        }.padding(12).frame(width: 220).foregroundStyle(appearance.ink)
                            .background(.white, in: RoundedRectangle(cornerRadius: 26))
                    }.buttonStyle(CraftPressStyle())
                }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("community.featured")
    }
    private func play(_ game: CommunityGame) {
        perform(game) {
            let result=try await store.communityRequest("/games/\(game.id)/play") as? [String:Any]
            guard let link=result?["url"] as? String, let url=URL(string:link), url.scheme=="https", url.host != nil else {
                throw CraftError(message:store.t("This game link cannot be opened.", "此游戏链接无法打开。"))
            }
            browser=CommunityBrowser(url:url)
        }
    }
    @ViewBuilder private func gameArtwork(_ game: CommunityGame, symbol: String) -> some View {
        if let url = URL(string: game.coverLink), url.scheme == "https", url.host == "3d-craft.web.app" {
            GeometryReader { geometry in
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                        .accessibilityLabel(game.title + store.t(" cover", " 封面"))
                        .accessibilityIdentifier("community.cover." + game.id)
                } placeholder: {
                    CommunityGameArtwork(symbol: symbol)
                }.frame(width: geometry.size.width, height: 146)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 20))
            }.frame(height: 146)
        } else { CommunityGameArtwork(symbol: symbol) }
    }
    private func vote(_ game: CommunityGame) {
        guard let uid=account.uid else { signIn=true; return }
        guard !busy.contains(game.id), let index=games.firstIndex(where:{$0.id==game.id}) else { return }
        let cat=category.rawValue
        let before=games[index]
        let liked = !before.myVotes.contains(cat)
        busy.insert(game.id); error=nil; requestID=UUID(); loading=false
        withAnimation(CraftMotion.gated(.snap, reduceMotion)) {
            games[index].votes[cat]=max(0,(before.votes[cat] ?? 0)+(liked ? 1 : -1))
            if liked { games[index].myVotes.append(cat) } else { games[index].myVotes.removeAll{$0==cat} }
            votePulse += 1
        }
        Task { @MainActor in
            defer { busy.remove(game.id) }
            do {
                guard let saved=try await store.communityRequest("/games/\(game.id)/vote",method:"PUT",body:["category":cat,"liked":liked]) as? [String:Any] else {
                    throw CraftError(message:"Vote response was incomplete")
                }
                guard account.uid==uid else { return }
                requestID=UUID();loading=false
                if let i=games.firstIndex(where:{$0.id==game.id}) {
                    withAnimation(CraftMotion.gated(.snap, reduceMotion)) {
                        games[i].votes=saved["votes"] as? [String:Int] ?? games[i].votes
                        games[i].myVotes=saved["myVotes"] as? [String] ?? games[i].myVotes
                    }
                }
            } catch {
                guard account.uid==uid else { return }
                if let i=games.firstIndex(where:{$0.id==game.id}) {
                    withAnimation(CraftMotion.gated(.snap, reduceMotion)) {
                        games[i].votes[cat]=before.votes[cat]
                        games[i].myVotes.removeAll{$0==cat}
                        if before.myVotes.contains(cat) { games[i].myVotes.append(cat) }
                    }
                }
                self.error=store.t("Your like couldn’t be saved. Tap the like button to try again.", "点赞未能保存，请再次点击重试。")
            }
        }
    }
    private func perform(_ game: CommunityGame, action: @escaping () async throws -> Void) {
        guard !busy.contains(game.id) else {return};busy.insert(game.id);error=nil
        Task { @MainActor in
            defer {busy.remove(game.id)}
            do {try await action()} catch {self.error=error.localizedDescription}
        }
    }
    private func load(more: Bool = false) async {
        let ticket=UUID();requestID=ticket;loading=true;error=nil
        let scope="\(category.rawValue)-\(mine)-\(account.uid ?? "guest")"
        if scope != loadedScope { games=[];loadedScope=scope }
        defer {if ticket==requestID {loading=false}}
        do {
            if mine {
                let rows=try await store.communityRequest("/mine") as? [[String:Any]] ?? []
                guard ticket==requestID else {return};games=rows.map(CommunityGame.init);hasMore=false
            } else {
                let result=try await store.communityRequest("/games?category=\(category.rawValue)&offset=\(more ? nextOffset : 0)") as? [String:Any] ?? [:]
                guard ticket==requestID else {return}
                let rows=(result["games"] as? [[String:Any]] ?? []).map(CommunityGame.init)
                if more { games += rows.filter { row in !games.contains(where:{$0.id==row.id}) } } else {games=rows}
                hasMore=result["hasMore"] as? Bool ?? false
                nextOffset=result["nextOffset"] as? Int ?? games.count
            }
        } catch {if ticket==requestID {self.error=error.localizedDescription}}
    }
}

private struct CommunityBlocksView: View {
    let onChanged: () -> Void
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @State private var blocks: [[String:String]] = []
    @State private var loading = true
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red); Button(store.t("Retry", "重试")) { Task { await load() } } }
                if loading { ProgressView() }
                else if blocks.isEmpty && error == nil { Text(store.t("No blocked creators", "暂无已屏蔽的创作者")) }
                ForEach(blocks, id: \.self) { block in
                    HStack {
                        Text(block["creator"] ?? store.t("Creator", "创作者"))
                        Spacer()
                        Button(store.t("Unblock", "取消屏蔽")) {
                            guard let id=block["id"] else { return }
                            busy=id;error=nil
                            Task { @MainActor in
                                defer { busy=nil }
                                do { _=try await store.communityRequest("/blocks/\(id)",method:"DELETE");await load();onChanged() }
                                catch { self.error=error.localizedDescription }
                            }
                        }.disabled(busy != nil)
                    }
                }
            }
            .navigationTitle(store.t("Blocked creators", "已屏蔽的创作者"))
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button(store.t("Done", "完成")) { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        loading=true;error=nil
        defer { loading=false }
        do { blocks=try await store.communityRequest("/blocks") as? [[String:String]] ?? [] }
        catch { self.error=error.localizedDescription }
    }
}

struct CommunitySubmissionView: View {
    var onPosted: () -> Void
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var title=""
    @State private var creator=""
    @State private var description=""
    @State private var link=""
    @State private var played=false
    @State private var rightsConfirmed=false
    @State private var clientId=UUID().uuidString
    @State private var working=false
    @State private var error: String?
    @State private var checkedLink: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Your game", "你的游戏")) {
                    TextField(store.t("Game title", "游戏名称"),text:$title).accessibilityIdentifier("community.title")
                    TextField(store.t("Creator name", "创作者名称"),text:$creator)
                    TextField(store.t("A short description", "简单介绍"),text:$description,axis:.vertical).lineLimit(2...4)
                }
                Section(store.t("Published game link", "已发布的游戏链接")) {
                    TextField("https://…", text: $link, axis: .vertical)
                        .lineLimit(2...4)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(working)
                        .accessibilityIdentifier("community.url")
                    Text(store.t("Use the playable game page, not a conversation or coding workspace link.", "使用可玩的游戏页面，不要使用聊天记录或编程工作区链接。")).font(.caption).foregroundStyle(.secondary)
                    Button(store.t("Check link", "检查链接")) { run {
                        let result=try await store.communityRequest("/check-link",method:"POST",body:["url":link]) as? [String:Any]
                        checkedLink=result?["url"] as? String
                    } }.disabled(link.isEmpty || working).accessibilityIdentifier("community.check")
                    if let checkedLink, let url=URL(string:checkedLink) {
                        Label(store.t("Public page opens", "可公开打开页面"),systemImage:"checkmark.circle.fill").foregroundStyle(.green)
                        Text(checkedLink)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        Button(store.t("Open and play-test", "打开并试玩")) {openURL(url)}
                        Toggle(store.t("I created this game and tested that it is playable.", "这是我创作的游戏，我已确认可以游玩。"),isOn:$played)
                        Toggle(store.t("I hold full rights to this game and grant 3D Craft permission to display and link to it in the community.", "我拥有此游戏的完整权利，并授权 3D Craft 在社区中展示及提供链接。"),isOn:$rightsConfirmed)
                            .accessibilityIdentifier("community.rightsConfirm")
                        Text(store.t("A publicly accessible link alone does not establish permission. Submissions must not infringe third-party copyrights or trademarks, and are subject to 3D Craft's Terms of Service.", "未经授权的公开链接不得提交。你必须拥有作品权利或获得授权。提交内容受 3D Craft 条款约束。"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error { Section {Text(error).foregroundStyle(.red)} }
                Section {
                    Text(store.t("Your game will be reviewed before its title, creator name, description and link are published. Player votes decide the rankings.", "审核通过后，游戏名称、创作者名称、介绍和链接将公开展示，玩家投票决定排名。")).font(.caption)
                    Button(store.t("Submit for review", "提交审核")) { run {
                        _=try await store.communityRequest("/games",method:"POST",body:["title":title,"creator":creator,"description":description,"url":checkedLink ?? link,"played":played,"rightsConfirmed":rightsConfirmed,"clientId":clientId])
                        onPosted();dismiss()
                    } }.disabled(working || checkedLink == nil || !played || !rightsConfirmed || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || creator.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("community.publish")
                    if working {ProgressView()}
                }
            }.navigationTitle(store.t("Share a game", "发布游戏")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) {Button(store.t("Cancel", "取消")) {dismiss()}.disabled(working)} }
                .onAppear {creator=CraftProfile.shared.displayName(chinese:store.isChinese)}
                .onChange(of:link) {_,_ in checkedLink=nil;played=false;rightsConfirmed=false}
                .interactiveDismissDisabled(working)
        }
    }
    private func run(_ action: @escaping () async throws -> Void) {
        working=true;error=nil
        Task { @MainActor in defer {working=false}; do {try await action()} catch {self.error=error.localizedDescription} }
    }
}
