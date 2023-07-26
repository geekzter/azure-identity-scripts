locals {
  azdo_api_version             = "7.1-preview.1"
  azdo_member_id               = jsondecode(data.http.azdo_member.response_body).id
  azdo_organization_id         = var.azdo_organization_id != null && var.azdo_organization_id != "" ? var.azdo_organization_id : [for a in jsondecode(data.http.azdo_organizations.response_body).value : a.accountId if a.accountName == local.azdo_organization_name][0]
}

data http azdo_member {
  url                          = "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=${local.azdo_api_version}"

  request_headers = {
    Accept                     = "application/json"
    Authorization              = "Bearer ${data.external.azdo_token.result.accessToken}"
  }

  lifecycle {
    postcondition {
      condition                = tonumber(self.status_code) < 300
      error_message            = "Could not retrieve member information from ${self.url}"
    }
    postcondition {
      condition                = can(jsondecode(self.response_body).id)
      error_message            = "Member information at ${self.url} not available ot in expected format"
    }
  }
}

data http azdo_organizations {
  url                          = "https://app.vssps.visualstudio.com/_apis/accounts?api-version=${local.azdo_api_version}&memberId=${local.azdo_member_id}"
  request_headers = {
    Accept                     = "application/json"
    Authorization              = "Bearer ${data.external.azdo_token.result.accessToken}"
  }

  lifecycle {
    postcondition {
      condition                = tonumber(self.status_code) < 300
      error_message            = "Could not retrieve account information from ${self.url}"
    }
    postcondition {
      condition                = length(jsondecode(self.response_body).value) > 0
      error_message            = "No organizations found for member ${local.azdo_member_id} at ${self.url}"
    }
  }
}
