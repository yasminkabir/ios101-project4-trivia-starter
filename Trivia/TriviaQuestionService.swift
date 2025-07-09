
import Foundation

struct TriviaAPIResponse: Decodable {
    let response_code: Int
    let results: [TriviaAPIQuestion]
}

struct TriviaAPIQuestion: Decodable {
    let category: String
    let type: String
    let question: String
    let correct_answer: String
    let incorrect_answers: [String]
}

struct TokenResponse: Decodable {
    let response_code: Int
    let token: String
}

extension String {
    func decodeBase64() -> String {
        guard let data = Data(base64Encoded: self),
              let decoded = String(data: data, encoding: .utf8) else {
            return self
        }
        return decoded
    }
}

// MARK: - Service Class
class TriviaQuestionService {
    private var sessionToken: String?

    // Fetch a token once and reuse it
    func getSessionToken(completion: @escaping () -> Void) {
        let tokenURL = URL(string: "https://opentdb.com/api_token.php?command=request")!

        URLSession.shared.dataTask(with: tokenURL) { data, _, _ in
            guard
                let data = data,
                let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data)
            else {
                print("Failed to get session token")
                completion()
                return
            }

            self.sessionToken = tokenResponse.token
            completion()
        }.resume()
    }

    func resetToken(completion: @escaping () -> Void) {
        guard let token = sessionToken else {
            completion()
            return
        }

        let resetURL = URL(string: "https://opentdb.com/api_token.php?command=reset&token=\(token)")!

        URLSession.shared.dataTask(with: resetURL) { _, _, _ in
            print("Token reset")
            completion()
        }.resume()
    }

    func fetchQuestions(amount: Int = 5, category: Int? = nil, difficulty: String? = nil, completion: @escaping ([TriviaQuestion]) -> Void) {
        func startFetch() {
            var urlString = "https://opentdb.com/api.php?amount=\(amount)&type=multiple&encode=base64"
            if let category = category {
                urlString += "&category=\(category)"
            }
            if let difficulty = difficulty {
                urlString += "&difficulty=\(difficulty)"
            }
            if let token = sessionToken {
                urlString += "&token=\(token)"
            }

            guard let url = URL(string: urlString) else {
                completion([])
                return
            }

            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data,
                      let apiResponse = try? JSONDecoder().decode(TriviaAPIResponse.self, from: data)
                else {
                    completion([])
                    return
                }

                if apiResponse.response_code == 4 {
                    // Token exhausted, reset and retry
                    self.resetToken {
                        self.fetchQuestions(amount: amount, category: category, difficulty: difficulty, completion: completion)
                    }
                    return
                }

                let questions = apiResponse.results.map { q in
                    TriviaQuestion(
                        category: q.category.decodeBase64(),
                        question: q.question.decodeBase64(),
                        correctAnswer: q.correct_answer.decodeBase64(),
                        incorrectAnswers: q.incorrect_answers.map { $0.decodeBase64() }
                    )
                }

                DispatchQueue.main.async {
                    completion(questions)
                }
            }.resume()
        }

        if sessionToken == nil {
            getSessionToken {
                startFetch()
            }
        } else {
            startFetch()
        }
    }
}
