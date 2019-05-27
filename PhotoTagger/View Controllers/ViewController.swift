//  ref: https://www.raywenderlich.com/35-alamofire-tutorial-getting-started

import UIKit
import SwiftyJSON
import Alamofire

class ViewController: UIViewController {

  // MARK: - IBOutlets
  @IBOutlet var takePictureButton: UIButton!
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var progressView: UIProgressView!
  @IBOutlet var activityIndicatorView: UIActivityIndicatorView!
  let token = "Basic xxx"

  // MARK: - Properties
  private var tags: [String]?
  private var colors: [PhotoColor]?

  // MARK: - View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()

    if !UIImagePickerController.isSourceTypeAvailable(.camera) {
      takePictureButton.setTitle("Select Photo", for: .normal)
    }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    imageView.image = nil
  }

  // MARK: - Navigation
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

    if segue.identifier == "ShowResults",
      let controller = segue.destination as? TagsColorsViewController {
      controller.tags = tags
      controller.colors = colors
    }
  }

  // MARK: - IBActions
  @IBAction func takePicture(_ sender: UIButton) {
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.allowsEditing = false

    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = .camera
    } else {
      picker.sourceType = .photoLibrary
      picker.modalPresentationStyle = .fullScreen
    }

    present(picker, animated: true)
  }
}

// MARK: - UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
    guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
      print("Info did not have the required UIImage for the Original Image")
      dismiss(animated: true)
      return
    }

    imageView.image = image
    
    // 1
    takePictureButton.isHidden = true
    progressView.progress = 0.0
    progressView.isHidden = false
    activityIndicatorView.startAnimating()
    
    upload(image: image,
           progressCompletion: { [weak self] percent in
            // 2
            self?.progressView.setProgress(percent, animated: true)
      },
           completion: { [weak self] tags, colors in
            // 3
            self?.takePictureButton.isHidden = false
            self?.progressView.isHidden = true
            self?.activityIndicatorView.stopAnimating()
            
            self?.tags = tags
            self?.colors = colors
            
            // 4
            self?.performSegue(withIdentifier: "ShowResults", sender: self)
    })
    
    dismiss(animated: true)
  }
}

extension ViewController {
  func upload(image: UIImage,
              progressCompletion: @escaping (_ percent: Float) -> Void,
              completion: @escaping (_ tags: [String]?, _ colors: [PhotoColor]?) -> Void) {
    // 1 The image that’s being uploaded needs to be converted to a Data instance.
    guard let imageData = UIImageJPEGRepresentation(image, 0.5) else {
      print("Could not get JPEG representation of UIImage")
      return
    }
    
    // 2 Here you convert the JPEG data blob (imageData) into a MIME multipart request to send to the Imagga content endpoint.
    Alamofire.upload(multipartFormData: { multipartFormData in
      multipartFormData.append(imageData,
                               withName: "imagefile",
                               fileName: "image.jpg",
                               mimeType: "image/jpeg")
    },
                     to: "http://api.imagga.com/v1/content",
                     headers: ["Authorization": token],
                     encodingCompletion: { encodingResult in
                      
                      switch encodingResult {
                      case .success(let upload, _, _):
                        upload.uploadProgress { progress in
                          progressCompletion(Float(progress.fractionCompleted))
                        }
                        upload.validate()
                        upload.responseJSON { response in
                          // 1 Check that the upload was successful, and the result has a value; if not, print the error and call the completion handler.
                          guard response.result.isSuccess,
                            let value = response.result.value else {
                              print("Error while uploading file: \(String(describing: response.result.error))")
                              completion(nil, nil)
                              return
                          }
                          
                          // 2 Using SwiftyJSON, retrieve the firstFileID from the response.
                          let firstFileID = JSON(value)["uploaded"][0]["id"].stringValue
                          print("Content uploaded with ID: \(firstFileID)")
                          
                          //3 Call the completion handler to update the UI. At this point, you don’t have any downloaded tags or colors, so simply call this with no data.
                          self.downloadTags(contentID: firstFileID) { tags in
                            self.downloadColors(contentID: firstFileID) { colors in
                              completion(tags, colors)
                            }
                          }
                          
                        }
                      case .failure(let encodingError):
                        print(encodingError)
                      }
    })
  }
  
  func downloadTags(contentID: String, completion: @escaping ([String]?) -> Void) {
    // 1 Perform an HTTP GET request against the tagging endpoint, sending the URL parameter content with the ID you received after the upload.
    Alamofire.request("http://api.imagga.com/v1/tagging",
                      parameters: ["content": contentID],
                      headers: ["Authorization": token])
      // 2 Check that the response was successful, and the result has a value; if not, print the error and call the completion handler.
      .responseJSON { response in
        guard response.result.isSuccess,
          let value = response.result.value else {
            print("Error while fetching tags: \(String(describing: response.result.error))")
            completion(nil)
            return
        }
        
        // 3 Using SwiftyJSON, retrieve the raw tags array from the response. Iterate over each dictionary object in the tags array, retrieving the value associated with the tag key.
        let tags = JSON(value)["results"][0]["tags"].array?.map { json in
          json["tag"].stringValue
        }
        
        // 4 Call the completion handler passing in the tags received from the service.
        completion(tags)
    }
  }
  
  func downloadColors(contentID: String, completion: @escaping ([PhotoColor]?) -> Void) {
    // 1.
    Alamofire.request("http://api.imagga.com/v1/colors",
                      parameters: ["content": contentID],
                      headers: ["Authorization": token])
      .responseJSON { response in
        // 2
        guard response.result.isSuccess,
          let value = response.result.value else {
            print("Error while fetching colors: \(String(describing: response.result.error))")
            completion(nil)
            return
        }
        
        print(JSON(value))
        
        // 3
        let photoColors = JSON(value)["results"][0]["info"]["image_colors"].array?.map { json in
          PhotoColor(red: json["r"].intValue,
                     green: json["g"].intValue,
                     blue: json["b"].intValue,
                     colorName: json["closest_palette_color"].stringValue)
        }
        
        // 4
        completion(photoColors)
    }
  }


  
}
