import Foundation
import PlaygroundSupport
PlaygroundPage.current.needsIndefiniteExecution = true


enum HttpMethod<Body> {
    case get
    case post(Body)
}

extension HttpMethod {
    var method: String {
        switch self {
        case .get: return "GET"
        case .post: return "POST"
        }
    }
}

struct Resource<A> {
    var urlRequest: URLRequest
    let parse: (Data) -> A?
}

extension Resource {
    func map<B>(_ transform: @escaping (A) -> B) -> Resource<B> {
        return Resource<B>(urlRequest: urlRequest) { self.parse($0).map(transform) }
    }
}

extension Resource where A: Decodable {
    init(get url: URL) {
        self.urlRequest = URLRequest(url: url)
        self.parse = { data in
            try? JSONDecoder().decode(A.self, from: data)
        }
    }
    
    init<Body: Encodable>(url: URL, method: HttpMethod<Body>) {
        urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.method
        switch method {
        case .get: ()
        case .post(let body):
            self.urlRequest.httpBody = try! JSONEncoder().encode(body)
        }
        self.parse = { data in
            try? JSONDecoder().decode(A.self, from: data)
        }
    }
}

extension URLSession {
    func load<A>(_ resource: Resource<A>, completion: @escaping (A?) -> ()) {
        dataTask(with: resource.urlRequest) { data, _, _ in
            completion(data.flatMap(resource.parse))
            }.resume()
    }
}

struct Episode: Codable {
    var number: Int
    var title: String
    var collection: String
}

struct Collection: Codable {
    var title: String
    var id: String
}

indirect enum CombinedResource<A> {
    case single(Resource<A>)
    case _sequence(CombinedResource<Any>, (Any) -> CombinedResource<A>)
}

extension CombinedResource {
    var asAny: CombinedResource<Any> {
        switch self {
        case let .single(r): return .single(r.map { $0 })
        case let ._sequence(l, transform): return ._sequence(l, { x in
            transform(x).asAny
        })
        }
    }
    
    func flatMap<B>(_ transform: @escaping (A) -> CombinedResource<B>) -> CombinedResource<B> {
        return CombinedResource<B>._sequence(self.asAny, { x in
            transform(x as! A)
        })
    }
    
    func map<B>(_ transform: @escaping (A) -> B) -> CombinedResource<B> {
        fatalError()
    }
    
    func zip<B>(_ other: CombinedResource<B>) -> CombinedResource<(A,B)> {
        fatalError()
    }
}

let episodes = Resource<[Episode]>(get: URL(string: "https://talk.objc.io/episodes.json")!)
let collections = Resource<[Collection]>(get: URL(string: "https://talk.objc.io/collections.json")!)

func loadEpisodes(_ completion: @escaping ([Episode]?) -> ()) {
    URLSession.shared.load(collections) { colls in
        guard let c = colls?.first else { completion(nil); return }
        URLSession.shared.load(episodes) { eps in
            completion(eps?.filter { $0.collection == c.id })
        }
    }
}

extension URLSession {
    func load<A>(_ resource: CombinedResource<A>, completion: @escaping (A?) -> ()) {
        switch resource {
        case let .single(r): load(r, completion: completion)
        case let ._sequence(l, transform):
            load(l) { result in
                guard let x = result else { completion(nil); return }
                self.load(transform(x), completion: completion)
            }
        }
    }
}

//loadEpisodes { print($0) }

extension Resource {
    var c: CombinedResource<A> {
        return .single(self)
    }
}

let eps: CombinedResource<[Episode]> = collections.map { $0.first! }.c.flatMap { c in
    episodes.map { eps in eps.filter { ep in ep.collection == c.id } }.c
}

URLSession.shared.load(eps) { print($0) }
