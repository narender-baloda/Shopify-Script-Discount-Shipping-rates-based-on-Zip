# ================================ Customizable Settings ================================
# ================================================================
# Discount Rate(s) by Country & Zip Codes(s)
#
# If one of the entered discount codes is used, the entered
# rate(s) are discounted by the entered amount
#
#   - 'zip_code_match_type' determines whether the below
#     strings should be an exact or partial match. Can be:
#       - ':exact' for an exact match
#       - ':partial' for a partial match
#   - 'zip_codes' is a list of strings to identify zip codes
#   - 'rate_match_type' determines whether the below strings
#     should be an exact or partial match. Can be:
#       - ':exact' for an exact match
#       - ':partial' for a partial match
#   - 'rate_names' is a list of strings to identify rates
#   - 'discount_type' is the type of discount to provide. Can be
#     either:
#       - ':percent'
#       - ':fixed'
#   - 'discount_amount' is the percentage/fixed discount to
#     apply
#   - 'discount_message' is the message to show when a discount
#     is applied
# ================================================================

DISCOUNT_FOR_ZIP_PROVINCE_COUNTRY = [
  {
    country_code: "CA",
    province_code: "BC",
    zip_code_match_type: :partial,
    zip_codes: ["M1R","A0B"],
    rate_match_type: :exact,
    rate_names: ["Canada Post Expedited (3 to 7 business days - exclude weekends)"],
    discount_type: :fixed,
    discount_amount: 18.75,
    discount_message: "FedEx has a mandatory Out-of-Delivery Area surcharge for your shipping zip code."
  },
]
# ================================ Script Code (do not edit) ================================
# ================================================================
# ZipCodeSelector
#
# Finds whether the supplied zip code matches any of the entered
# strings.
# ================================================================
class ZipCodeSelector
  def initialize(match_type, zip_codes)
    @comparator = match_type == :exact ? '==' : 'include?'
    @zip_codes = zip_codes.map { |zip_code| zip_code.upcase.strip }
  end
  def match?(zip_code)
    @zip_codes.any? { |zip| zip_code.to_s.upcase.strip.send(@comparator, zip) }
  end
end
# ================================================================
# RateNameSelector
#
# Finds whether the supplied rate name matches any of the entered
# names.
# ================================================================
class RateNameSelector
  def initialize(match_type, rate_names)
    @match_type = match_type
    @comparator = match_type == :exact ? '==' : 'include?'
    @rate_names = rate_names&.map { |rate_name| rate_name.downcase.strip }
  end
  def match?(shipping_rate)
    if @match_type == :all
      true
    else
      @rate_names.any? { |name| shipping_rate.name.downcase.send(@comparator, name) }
    end
  end
end
# ================================================================
# DiscountApplicator
#
# Applies the entered discount to the supplied shipping rate.
# ================================================================
class DiscountApplicator
  def initialize(discount_type, discount_amount, discount_message)
    @discount_type = discount_type
    @discount_message = discount_message

    @discount_amount = if discount_type == :percent
      discount_amount * 0.01
    else
      Money.new(cents: 100) * discount_amount
    end
  end

  def apply(shipping_rate)
    rate_discount = if @discount_type == :percent
      shipping_rate.price * @discount_amount
    else
      @discount_amount
    end

    shipping_rate.apply_discount(rate_discount, message: @discount_message)
  end
end
# ================================================================
# DiscountRatesForZipProvinceCountryCampaign
# ================================================================
class DiscountRatesForZipProvinceCountryCampaign
  def initialize(campaigns)
    @campaigns = campaigns
  end
  def run(cart, shipping_rates)
    address = cart.shipping_address
    @campaigns.each do |campaign|
      zip_code_selector = ZipCodeSelector.new(campaign[:zip_code_match_type], campaign[:zip_codes])
      rate_name_selector = RateNameSelector.new(campaign[:rate_match_type], campaign[:rate_names])
      if address.nil?
        full_match = false
      else
        country_match =  address.country_code.upcase.strip == campaign[:country_code].upcase.strip
        province_match = address.province_code.upcase.strip == campaign[:province_code].upcase.strip
        zip_match = zip_code_selector.match?(address.zip)
        #full_match = country_match && province_match && zip_match
        full_match = country_match && zip_match
      end

      discount_applicator = DiscountApplicator.new(
        campaign[:discount_type],
        campaign[:discount_amount],
        campaign[:discount_message],
      )
      
      shipping_rates.each do |shipping_rate|
          if rate_name_selector.match?(shipping_rate) && full_match
            next unless shipping_rate.source == "shopify"
            discount_applicator.apply(shipping_rate)
        end
      end
    end
  end
end
CAMPAIGNS = [
  DiscountRatesForZipProvinceCountryCampaign.new(DISCOUNT_FOR_ZIP_PROVINCE_COUNTRY),
]
CAMPAIGNS.each do |campaign|
  campaign.run(Input.cart, Input.shipping_rates)
end

Output.shipping_rates = Input.shipping_rates