//
//  ViewController.swift
//  Insultr
//
//  Created by Nick Gerancher on 10/18/20.
//

import UIKit
import FirebaseStorage

extension Dictionary {
    func percentEncoded() -> Data? {
        return map { key, value in
            let escapedKey = "\(key)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            let escapedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            return escapedKey + "=" + escapedValue
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        return allowed
    }()
}

struct FaceEmotion: Decodable, Encodable {
    var anger: Float64?
    var disgust: Float64?
    var fear: Float64?
    var happiness: Float64?
    var neutral: Float64?
    var sadness: Float64?
    var surprise: Float64?
    
    enum CodingKeys: String, CodingKey {
        case anger = "anger"
        case disgust = "disgust"
        case fear = "fear"
        case happiness = "happiness"
        case neutral = "neutral"
        case sadness = "sadness"
        case surprise = "surprise"
    }
}

struct FaceAge: Decodable, Encodable {
    var value: Int16?
    
    enum CodingKeys: String, CodingKey {
        case value = "value"
    }
}

struct FaceGender: Decodable, Encodable {
    var value: String?
    
    enum CodingKeys: String, CodingKey {
        case value = "value"
    }
}

struct FaceRace: Decodable, Encodable {
    var value: String?
    
    enum CodingKeys: String, CodingKey {
        case value = "value"
    }
}

struct FaceAttributes: Decodable, Encodable {
    var age: FaceAge?
    var gender: FaceGender?
    var ethnicity: FaceRace?
    var emotion: FaceEmotion?
    
    enum CodingKeys: String, CodingKey {
        case age = "age"
        case gender = "gender"
        case ethnicity = "ethnicity"
        case emotion = "emotion"
    }
}

struct Face: Decodable, Encodable {
    var top: Float64?
    var left: Float64?
    var width: Float64?
    var height: Float64?
    var attributes: FaceAttributes?
    
    enum CodingKeys: String, CodingKey {
        case top = "top"
        case left = "left"
        case width = "width"
        case height = "height"
        case attributes = "attributes"
    }
}

struct FaceResponse: Codable {
    var faces: [Face?]
    
    enum CodingKeys: String, CodingKey {
        case faces = "faces"
    }
}

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var insultBtn: UIButton!
    
    private let store = Storage.storage().reference()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        insultBtn.isEnabled = false
    
        guard let urlStr = UserDefaults.standard.value(forKey: "current_url") as? String,
        let url = URL(string: urlStr) else {
            print("URL ERROR")
            self.insultBtn.isEnabled = false
            return
        }
        
        let task = URLSession.shared.dataTask(with: url, completionHandler: {data, _, error in
            guard let data = data, error == nil else {
                print("DATA ERROR")
                self.insultBtn.isEnabled = false
                return
            }
            
            DispatchQueue.main.async {
                print("Using image: \(urlStr)")
                let image = UIImage(data: data)
                self.imageView.image = image
                self.insultBtn.isEnabled = true
                if image == nil {
                    self.insultBtn.isEnabled = false
                }
            }
        })
        
        task.resume()
    }
        
    @IBAction func didTapLibraryPickerButton(_ sender: UIButton) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.allowsEditing = true
        present(picker, animated: true)
    }
    
    @IBAction func insultButton(_ sender: UIButton) {
        guard let urlStr = UserDefaults.standard.value(forKey: "current_url") as? String else {
            print("URLSTR ERROR")
            self.insultBtn.isEnabled = false
            return
        }
        
        guard let api = URL(string: "https://rapidapi.p.rapidapi.com/facepp/v3/detect") else { return
        }
        var request = URLRequest(url: api)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("faceplusplus-faceplusplus.p.rapidapi.com", forHTTPHeaderField: "x-rapidapi-host")
        request.setValue("29a657df82mshc24702e4bca811fp1685b0jsn024813182074", forHTTPHeaderField: "x-rapidapi-key")
        request.httpMethod = "POST"
        
        let params: [String: Any] = [
            "image_url": urlStr,
            "return_attributes": "gender,age,smiling,emotion,ethnicity,beauty,skinstatus"
        ]
        
        request.httpBody = params.percentEncoded()
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, let response = response as? HTTPURLResponse, error == nil else {
                print("DATA NOT OKAY")
                return
            }
            
            guard (200 ... 299) ~= response.statusCode else {
                print("Status code not okay! \(response.statusCode)")
                print(response.description)
                return
            }
            
            //print(String(description: data))
            
            DispatchQueue.main.async {
                let decoder = JSONDecoder()
                do {
                    let face = try decoder.decode(FaceResponse.self, from: data)
                    self.processAttribs(data: face.faces[0])
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
        
        task.resume()
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)
        guard let image = info[UIImagePickerController.InfoKey.editedImage] as? UIImage else {
            self.insultBtn.isEnabled = false
            return
        }
        
        guard let imageData = image.pngData() else {
            self.insultBtn.isEnabled = false
            return
        }
        
        let imageID = "images/" + UUID().uuidString + ".png"
        
        store.child(imageID).putData(imageData, metadata: nil, completion: {_, error in
            guard error == nil else {
                print("An error occurred while uploading the image!")
                self.insultBtn.isEnabled = false
                return
            }
            
            self.store.child(imageID).downloadURL(completion: {url, error in
                guard let url = url, error == nil else {
                    self.insultBtn.isEnabled = false
                    return
                }
                
                let urlStr = url.absoluteString
                print("Got download url: \(urlStr)")
                
                DispatchQueue.main.async {
                    self.imageView.image = image
                }
                
                self.insultBtn.isEnabled = true
                UserDefaults.standard.set(urlStr, forKey: "current_url")
            })
        })
        
        
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    func findAge(data: FaceAge?) -> String {
        if ((data?.value) != nil) {
            return String((data?.value)!)
        }
        return "-1"
    }
    
    func findEmotion(data: FaceEmotion?) -> String {
        if ((data?.anger) != nil) && (data?.anger)! >= 55.0 {
            return "Angry"
        } else if ((data?.disgust) != nil) && (data?.disgust)! >= 55.0 {
            return "Digusted"
        } else if ((data?.fear) != nil) && (data?.fear)! >= 55.0 {
            return "Scared"
        } else if ((data?.neutral) != nil) && (data?.neutral)! >= 55.0 {
            return "Neutral"
        } else if ((data?.sadness) != nil) && (data?.sadness)! >= 55.0 {
            return "Sad"
        } else if ((data?.surprise) != nil) && (data?.surprise)! >= 55.0 {
            return "Surprised"
        } else if ((data?.happiness) != nil) && (data?.happiness)! >= 55.0 {
            return "Happy"
        } else {
            return "Unknown?"
        }
    }
    
    func processAttribs(data: Face?) {
        let funnyStr = """
            \nYour Age: \(self.findAge(data: data?.attributes?.age))\n
            Your Emotion: \(self.findEmotion(data: data?.attributes?.emotion))\n
        """
        
        let alert = UIAlertController(title: "You", message: "Here are some things I noticed about you...\n\(funnyStr)", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
        // alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))

        self.present(alert, animated: true)
    }
}

