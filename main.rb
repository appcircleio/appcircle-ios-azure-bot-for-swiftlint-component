require 'json'
require 'net/http'
require 'uri'
require 'base64'

def get_env_variable(key)
  return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end

$organization_name = get_env_variable('AC_AZURE_ORG_NAME')
$project_name = get_env_variable('AC_AZURE_PROJECT_NAME')
$repository = get_env_variable('AC_AZURE_REPO_NAME')
$base_url = get_env_variable('AC_AZURE_BASE_URL')
azure_api_key = get_env_variable('AC_AZURE_API_KEY')
$basic_token = "Basic #{Base64.strict_encode64(":#{azure_api_key}")}"
$json_content = "application/json"



$output_dir = get_env_variable("AC_OUTPUT_DIR") || abort('Missing output direction.')
$ac_pr_number = get_env_variable('AC_PULL_NUMBER') || abort('Missing Pull Number.')
$azure_api_version = get_env_variable('AC_AZURE_API_VERSION')
ac_domain_name = get_env_variable('AC_DOMAIN_NAME')
ac_build_profile_id = get_env_variable('AC_BUILD_PROFILE_ID')
$swiftlint_file_path = get_env_variable('AC_LINT_PATH')
$ac_build_profile_url = "https://#{ac_domain_name}/build/detail/#{ac_build_profile_id}"

def contains_warnings_or_error?(swiftlint_results)
  swiftlint_results.each_line do |line|
    if line.include?("warning:") || line.include?("error:")
      return true
    end
  end
  return false
end

def extract_error_and_warning_count(swiftlint_results)
  error_count = 0
  warning_count = 0
  swiftlint_results.each_line do |line|
    if line.include?("error:")
      error_count += 1
    elsif line.include?("warning:")
      warning_count += 1
    end
  end
  [error_count, warning_count]
end

def prepare_message_total_errors(swiftlint_results)
  error_count, warning_count = extract_error_and_warning_count(swiftlint_results)
  message = "# Summary based on SwiftLint results run from Appcircle:"
  if error_count > 0 || warning_count > 0
    message += "\n\n## :no_entry: Errors:\n"
    message += "- Total: #{error_count}\n"
    message += "\n## :warning: Warnings:\n"
    message += "- Total: #{warning_count}\n"
    message += "\n## :clipboard: Appcircle SwiftLint Build Link:\n"
    message += "- #{$ac_build_profile_url}"
  else
    message += "\n\nNo Swiftlint Error or Warning."
  end
  return message
end

def add_comment_to_pr(warning_message)
  
  url = URI("#{$base_url}/#{$organization_name}/#{$project_name}/_apis/git/repositories/#{$repository}/pullRequests/#{$ac_pr_number}/threads?api-version=#{$azure_api_version}")
  https = Net::HTTP.new(url.host, url.port)
  https.use_ssl = true
  request = Net::HTTP::Post.new(url)
  request["Authorization"] = $basic_token
  request["Content-Type"] = $json_content
  
  request.body = JSON.dump({
    "comments": [
      {
        "content": warning_message
      }
    ],
  })
  response = https.request(request)

  if response.code.to_i == 200
    puts "Comment added to PR ##{$ac_pr_number} successfully."
  else
    abort "Error adding comment to PR ##{$ac_pr_number}. \nResponse Message: #{response.message}"
  end
end

def change_status(status_err_message, statusState)

  url = URI("#{$base_url}/#{$organization_name}/#{$project_name}/_apis/git/repositories/#{$repository}/pullRequests/#{$ac_pr_number}/statuses?api-version=7.1-preview.1")

  https = Net::HTTP.new(url.host, url.port)
  https.use_ssl = true
  request = Net::HTTP::Post.new(url)
  request["Authorization"] = $basic_token
  request["Content-Type"] = $json_content
  
  request.body = JSON.dump({
    "context": {
      "genre": "",
      "name": "Success"
    },
    "state": statusState,
    "description": status_err_message
  })
  response = https.request(request)

  if response.code.to_i == 200
    puts "Status changed to PR ##{$ac_pr_number} successfully."
  else
    abort "Error changing status to PR ##{$ac_pr_number}. \nResponse Message: #{response.message}"
  end
end

if File.exist?($swiftlint_file_path)
  
  swiftlint_results = File.read($swiftlint_file_path)
  error_count, warning_count = extract_error_and_warning_count(swiftlint_results)
  
  if contains_warnings_or_error?(swiftlint_results)
    puts "PR ##{$ac_pr_number} stopped successfully due to SwiftLint warnings."
    warning_message = prepare_message_total_errors(swiftlint_results)
    status_err_message = "Some errors were returned from the SwiftLint report for PR ##{$ac_pr_number}, Appcircle stopped Build."
    statusState = "failed"
    add_comment_to_pr(warning_message)
    change_status(status_err_message, statusState)
    puts "Workflow stopped due to include Warning or Error"
    abort status_err_message
  else
    puts "PR ##{$ac_pr_number} is ready to review! No warnings, No violation"
    # Uyarı mesajını hazırla
    warning_message = "PR #{$ac_pr_number} is ready to review!\n- Errors: #{error_count}\n- Warnings: #{warning_count}\nNo Error, No Warning"
    status_err_message = "PR ##{$ac_pr_number} is clear and ready to review."
    statusState = "succeeded"
    # PR altına yorum olarak uyarı mesajını ekle
    add_comment_to_pr(warning_message)
    change_status(status_err_message, statusState)
  end
else
  abort "SwiftLint results file not found for PR ##{$ac_pr_number}."
end
