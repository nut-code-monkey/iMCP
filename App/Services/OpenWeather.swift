import Foundation
import MCP
import OSLog
import CoreLocation
import Ontology

private let log = Logger.service("weather")

struct OpenWeatherMapService: Service {
    static var shared = OpenWeatherMapService()
    var key = Bundle.main.object(forInfoDictionaryKey: "OPEN_WEATHER_KEY")
    
    var tools: [Tool] {
        guard let key = key as? String else { return [] }
        let api = OpenWeatherMapAPI(key: key)
        return [
            Tool(
                name: "weather_current",
                description:
                    "Get current weather for a location",
                inputSchema: .object(
                    properties: [
                        "latitude": .number(description: "Latitude"),
                        "longitude": .number(description: "Longitude"),
                    ],
                    required: ["latitude", "longitude"],
                    additionalProperties: false
                ),
                annotations: .init(
                    title: "Get Current Weather",
                    readOnlyHint: true,
                    openWorldHint: true
                )
            ) { arguments in
                guard let latitude = arguments["latitude"]?.number,
                      let longitude = arguments["longitude"]?.number
                else {
                    log.error("Invalid coordinates")
                    throw NSError(
                        domain: "WeatherServiceError",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid coordinates lat:\(String(describing: arguments["latitude"])) lon: \(String(describing: arguments["longitude"]))"]
                    )
                }
                
                let weather = try await api.current(
                    lat: latitude,
                    lon: longitude,
                    lang: .Ukrainian,
                    key: key,
                    units: .currentLocale
                )
                
                return WeatherCondition(weather: weather, unit: .currentLocale)
            }
        ]
    }
    
    private struct WeatherCondition: Encodable {
        let dateTime: Date
        let temperature: Measurement<UnitTemperature>
        let feelsLike: Measurement<UnitTemperature>
        let windSpeed: Measurement<UnitSpeed>
        let humidityPercentage0to1Scale: Double
        let condition: String?
        
        
        init(weather: OpenWeatherMapAPI.WeatherResponce, unit: OpenWeatherMapAPI.Units) {
            dateTime = weather.date
            temperature = Measurement(value: weather.main.temp, unit: unit.temperature)
            feelsLike = Measurement(value: weather.main.feelsLike, unit: unit.temperature)
            windSpeed = Measurement(value: weather.wind.speed, unit: unit.speed)

            humidityPercentage0to1Scale = weather.main.humidity
            condition = weather.weather.first?.label
        }
    }
}

extension Value {
    var number: Double? {
        switch self {
        case .double(let value): value
        case .int(let value): Double(value)
        default: nil
        }
    }
}

struct OpenWeatherMapAPI {
    let key: String
    enum OWMError: Error {
        case invalidURL
        case invalidResponse
    }
    
    enum Units: String {
        static var currentLocale: Units {
            switch UnitTemperature(forLocale: Locale.current) {
            case .celsius: .metric
            case .fahrenheit: .imperial
            default: .standard
            }
        }
        case metric
        case imperial
        case standard
        
        var temperature: UnitTemperature {
            switch self {
            case .imperial: .fahrenheit
            case .metric: .celsius
            case .standard: .kelvin
            }
        }
        
        var speed: UnitSpeed {
            switch self {
            case .imperial: .milesPerHour
            case .metric: .metersPerSecond
            case .standard: .metersPerSecond
            }
        }
    }
    
    // https://api.openweathermap.org/data/2.5/forecast
    // https://openweathermap.org/api/forecast5?collection=current_forecast
    
    // http://api.openweathermap.org/data/2.5/air_pollution
    // https://openweathermap.org/api/air-pollution?collection=environmental
    
    func current(lat: Double, lon: Double, lang: Lang? = nil, key: String, units: Units = .metric) async throws -> WeatherResponce {
        let url = "https://api.openweathermap.org/data/2.5/weather?lat=\(lat)&lon=\(lon)&appid=\(key)&lang=\(lang.code)&units=\(units.rawValue)"
            // https://openweathermap.org/api/current?collection=current_forecast
            
        guard let url = URL(string: url) else {
            throw OWMError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let response = response as? HTTPURLResponse,  200 ... 299 ~= response.statusCode else {
            throw OWMError.invalidResponse
        }

        return try JSONDecoder().decode(WeatherResponce.self, from: data)
    }
    
    struct WeatherResponce: Codable {
        let dt: Int
        var date: Date { Date(timeIntervalSince1970: TimeInterval(dt)) }
        
        let coord: Coord
        struct Coord: Codable {
            let lat: Double
            let lon: Double
        }
        let weather: [Weather]
        struct Weather: Codable {
            let id: Int
            let main: String // Rain
            let label: String //"moderate rain"
            let icon: String
            
            enum CodingKeys: String, CodingKey {
                case id = "id"
                case main = "main"
                case label = "description"
                case icon = "icon"
            }
        }
        
        let main: WeatherMain
        struct WeatherMain: Codable {
            let temp: Double
            let feelsLike: Double
            let tempMin: Double
            let tempMax: Double
            let pressure: Double
            let humidity: Double // %
            
            enum CodingKeys: String, CodingKey {
                case temp = "temp"
                case feelsLike = "feels_like"
                case tempMin = "temp_min"
                case tempMax = "temp_max"
                case humidity = "humidity"
                case pressure = "pressure"
            }
        }
        
        let rain: Precipitation?
        let snow: Precipitation?
        struct Precipitation: Codable {
            let mmPerHour: Int
            enum CodingKeys: String, CodingKey {
                case mmPerHour = "1h"
            }
        }
        
        let wind: Wind
        struct Wind: Codable {
            let speed: Double
            let deg: Double
        }
        
        let sys: Sys
        struct Sys: Codable {
            let country: String?
            var sunriseDate: Date { Date(timeIntervalSince1970: TimeInterval(sunrise)) }
            let sunrise: Int
            var sunsetDate: Date { Date(timeIntervalSince1970: TimeInterval(sunset)) }
            let sunset: Int
        }
    }
    
    enum Lang: String {
        case Albanian = "sq"
        case Afrikaans = "af"
        case Arabic = "ar"
        case Azerbaijani = "az"
        case Basque = "eu"
        case Belarusian = "be"
        case Bulgarian = "bg"
        case Catalan = "ca"
        case ChineseSimplified = "zh_cn"
        case ChineseTraditional = "zh_tw"
        case Croatian = "hr"
        case Czech = "cz"
        case Danish = "da"
        case Dutch = "nl"
        case English = "en"
        case Finnish = "fi"
        case French = "fr"
        case Galician = "gl"
        case German = "de"
        case Greek = "el"
        case Hebrew = "he"
        case Hindi = "hi"
        case Hungarian = "hu"
        case Icelandic = "is"
        case Indonesian = "id"
        case Italian = "it"
        case Japanese = "ja"
        case Korean = "kr"
        case Kurmanji = "ku"
        case Latvian = "la"
        case Lithuanian = "lt"
        case Macedonian = "mk"
        case Norwegian = "no"
        case Persian = "fa"
        case Polish = "pl"
        case Portuguese = "pt"
        case PortuguêsBrasil = "pt_br"
        case Romanian = "ro"
        case Russian = "ru"
        case Serbian = "sr"
        case Slovak = "sk"
        case Slovenian = "sl"
        case Spanish = "es"
        case Swedish = "se"
        case Thai = "th"
        case Turkish = "tr"
        case Ukrainian = "ua"
        case Vietnamese = "vi"
        case Zulu = "zu"
    }
}

extension OpenWeatherMapAPI.Lang? {
    var code: String {
        if let code = self {
            code.rawValue
        } else {
            OpenWeatherMapAPI.Lang.English.rawValue
        }
    }
}
