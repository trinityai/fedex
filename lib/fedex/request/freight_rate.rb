require 'fedex/request/base'

module Fedex
  module Request
    class FreightRate < Base
      def process_request
        api_response = self.class.post(api_url, :body => build_xml)
        puts api_response if @debug
        response = parse_response(api_response)
        if success?(response)
          rate_reply_details = response[:rate_reply][:rate_reply_details] || []
          rate_reply_details = [rate_reply_details] if rate_reply_details.is_a?(Hash)

          rate_reply_details.map do |rate_reply|
            rate_details = [rate_reply[:rated_shipment_details]].flatten.first[:shipment_rate_detail]
            rate_details.merge!(service_type: rate_reply[:service_type])
            Fedex::Rate.new(rate_details)
          end
        else
          error_message = if response[:rate_reply]
            [response[:rate_reply][:notifications]].flatten.first[:message]
          else
            "#{api_response["Fault"]["detail"]["fault"]["reason"]}\n--#{api_response["Fault"]["detail"]["fault"]["details"]["ValidationFailureDetail"]["message"].join("\n--")}"
          end rescue $1
          raise RateError, error_message
        end
      end

      private

      def add_requested_shipment(xml)
        xml.RequestedShipment{
          xml.DropoffType @shipping_options[:drop_off_type] ||= "REGULAR_PICKUP"
          xml.ServiceType service_type if service_type
          xml.PackagingType @shipping_options[:packaging_type] ||= "YOUR_PACKAGING"
          add_shipper(xml)
          add_recipient(xml)
          add_shipping_charges_payment(xml)
          add_freight_shipment_detail(xml)
          xml.RateRequestTypes "ACCOUNT"
          xml.Packages @packages.size
        }
      end

      def build_xml
        ns = "http://fedex.com/ws/rate/v#{service[:version]}"
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.RateRequest(:xmlns => ns){
            add_web_authentication_detail(xml)
            add_client_detail(xml)
            add_version(xml)
            xml.ReturnTransitAndCommit 1
            add_requested_shipment(xml)
          }
        end
        builder.doc.root.to_xml
      end

      def service
        { :id => 'crs', :version => 14 }
      end

      def success?(response)
        response[:rate_reply] &&
          %w{SUCCESS WARNING NOTE}.include?(response[:rate_reply][:highest_severity])
      end

      def add_shipper(xml)
        xml.Shipper{
          xml.AccountNumber @credentials.account_number
          xml.Contact{
            xml.PersonName @shipper[:name]
            xml.CompanyName @shipper[:company]
            xml.PhoneNumber @shipper[:phone_number]
          }
          xml.Address {
            Array(@shipper[:address]).take(2).each do |address_line|
              xml.StreetLines address_line
            end
            xml.City @shipper[:city]
            xml.StateOrProvinceCode @shipper[:state]
            xml.PostalCode @shipper[:postal_code]
            xml.CountryCode @shipper[:country_code]
            xml.Residential 0
          }
        }
      end

      def add_shipping_charges_payment(xml)
        xml.ShippingChargesPayment{
          xml.PaymentType "SENDER"
        }
      end

      def add_freight_shipment_detail(xml)
        xml.FreightShipmentDetail{
          xml.FedExFreightAccountNumber @credentials.account_number
          xml.FedExFreightBillingContactAndAddress{
            xml.Address{
              Array(@shipper[:address]).take(2).each do |address_line|
                xml.StreetLines address_line
              end
              xml.City @shipper[:city]
              xml.StateOrProvinceCode @shipper[:state]
              xml.PostalCode @shipper[:postal_code]
              xml.CountryCode @shipper[:country_code]
              xml.Residential 0
            }
          }
          xml.Role "SHIPPER"
          xml.CollectTermsType "STANDARD"
          xml.Coupons
          xml.ClientDiscountPercent 0
          xml.PalletWeight{
            xml.Units "LB"
            xml.Value 10
          }
          xml.ShipmentDimensions{
            xml.Length @packages[0][:dimensions][:length]
            xml.Width @packages[0][:dimensions][:width]
            xml.Height @packages[0][:dimensions][:height]
            xml.Units @packages[0][:dimensions][:units]
          }
          add_packages(xml)
        }
      end

      def add_packages(xml)
        @packages.each do |package|
          xml.LineItems{
            xml.FreightClass "CLASS_050"
            xml.Weight{
              xml.Units package[:weight][:units]
              xml.Value package[:weight][:value]
            }
            xml.Dimensions{
              xml.Length package[:dimensions][:length]
              xml.Width package[:dimensions][:width]
              xml.Height package[:dimensions][:height]
              xml.Units package[:dimensions][:units]
            }
          }
        end
      end

    # private

    end
  end
end

