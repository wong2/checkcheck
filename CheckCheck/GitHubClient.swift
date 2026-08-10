import Foundation

enum GitHubError: LocalizedError {
    case invalidResponse
    case requestFailed(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned an invalid response."
        case let .requestFailed(status, message):
            message.isEmpty ? "GitHub request failed (HTTP \(status))." : message
        }
    }
}

private struct GitHubErrorResponse: Decodable {
    let message: String
}

actor GitHubClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func user(token: String) async throws -> GitHubUser {
        try await request(path: "/user", token: token)
    }

    func repositories(token: String) async throws -> [GitHubRepository] {
        var repositories: [GitHubRepository] = []
        var page = 1

        while true {
            let pageRepositories: [GitHubRepository] = try await request(
                path: "/user/repos",
                queryItems: [
                    URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                    URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ],
                token: token
            )
            repositories.append(contentsOf: pageRepositories)
            guard pageRepositories.count == 100 else { return repositories }
            page += 1
        }
    }

    func checkRuns(
        repository: GitHubRepository,
        sha: String,
        token: String
    ) async throws -> [GitHubCheckRun] {
        let response: CheckRunsResponse = try await request(
            path: "/repos/\(encodedName(repository))/commits/\(sha)/check-runs",
            queryItems: [
                URLQueryItem(name: "filter", value: "all"),
                URLQueryItem(name: "per_page", value: "100")
            ],
            token: token
        )
        return response.checkRuns
    }

    func checkRuns(
        repository: GitHubRepository,
        shas: [String],
        token: String
    ) async -> [String: [GitHubCheckRun]] {
        await withTaskGroup(of: (String, [GitHubCheckRun]?).self) { group in
            for sha in shas {
                group.addTask {
                    let runs = try? await self.checkRuns(
                        repository: repository,
                        sha: sha,
                        token: token
                    )
                    return (sha, runs)
                }
            }

            var runsBySHA: [String: [GitHubCheckRun]] = [:]
            for await (sha, runs) in group {
                if let runs {
                    runsBySHA[sha] = runs
                }
            }
            return runsBySHA
        }
    }

    func commits(
        repository: GitHubRepository,
        limit: Int,
        token: String
    ) async throws -> [GitHubCommit] {
        try await request(
            path: "/repos/\(encodedName(repository))/commits",
            queryItems: [
                URLQueryItem(name: "sha", value: repository.defaultBranch),
                URLQueryItem(name: "per_page", value: String(limit))
            ],
            token: token
        )
    }

    private func encodedName(_ repository: GitHubRepository) -> String {
        repository.fullName
            .split(separator: "/")
            .map(String.init)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
            .joined(separator: "/")
    }

    private func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String
    ) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = path
        components.queryItems = queryItems

        guard let url = components.url else { throw GitHubError.invalidResponse }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CheckCheck", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? decoder.decode(GitHubErrorResponse.self, from: data).message) ?? ""
            throw GitHubError.requestFailed(status: response.statusCode, message: message)
        }
        return try decoder.decode(T.self, from: data)
    }
}
