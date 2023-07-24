locals {
  azdo_member_id               = jsondecode(data.http.azdo_member.response_body).id
  azdo_organization_id         = var.azdo_organization_id != null && var.azdo_organization_id != "" ? var.azdo_organization_id : [for a in jsondecode(data.http.azdo_organizations.response_body).value : a.accountId if a.accountName == local.azdo_organization_name][0]
}

data http azdo_member {
  url                          = "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1-preview.1"

  request_headers = {
    Accept                     = "application/json"
    Authorization              = "Bearer ${data.external.azdo_token.result.accessToken}"
  }

  lifecycle {
    postcondition {
      condition                = tonumber(self.status_code) < 300
      error_message            = "Could not retrieve member information"
    }
  }
}

data http azdo_organizations {
  url                          = "https://app.vssps.visualstudio.com/_apis/accounts?api-version=7.1-preview.1&memberId=${local.azdo_member_id}"
  request_headers = {
    Accept                     = "application/json"
    Authorization              = "Bearer ${data.external.azdo_token.result.accessToken}"
  }

  lifecycle {
    postcondition {
      condition                = tonumber(self.status_code) < 300
      error_message            = "Could not retrieve account information"
    }
    postcondition {
      condition                = length(jsondecode(self.response_body).value) > 0
      error_message            = "No organizations found for member ${local.azdo_member_id}"
    }
  }
}
