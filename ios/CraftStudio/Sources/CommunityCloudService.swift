import Foundation

/// Vote presentation helper; all persistence goes through the authenticated cloud API.
@MainActor
enum CommunityCloudService {
    static func applyingVote(to game: [String:Any], existing: [String], category: String, liked: Bool) -> [String:Any] {
        var result=game
        var cats=Set(existing)
        let wasLiked=cats.contains(category)
        if liked { cats.insert(category) } else { cats.remove(category) }
        var counts=game["votes"] as? [String:Int] ?? [:]
        counts[category]=max(0,(counts[category] ?? 0)+(wasLiked == liked ? 0 : liked ? 1 : -1))
        result["votes"]=counts;result["likes"]=counts.values.reduce(0,+)
        result["myVotes"]=cats.sorted()
        return result
    }

}
