class TwoFactor::Sms < ::TwoFactor
  attr_accessor :send_code_phase
  attr_accessor :country, :phone_number

  validates_presence_of :phone_number, if: :send_code_phase
  validate :valid_phone_number_for_country

  def verify?
    if !expired? && otp_secret == otp
      touch(:last_verify_at)
      true
    else
      if otp.blank?
        errors.add :otp, :blank
      else
        errors.add :otp, :invalid
      end
      false
    end
  end

  def sms_message
    I18n.t('sms.verification_code', code: otp_secret)
  end

  def send_otp
    refresh! if expired?
    save_phone_number if send_code_phase
    if self.source
      AMQPQueue.enqueue(:sms_notification, phone: phone_number, message: sms_message)
      true
    else
      false
    end
  end

  def active!
    super
    if member.phone_number == self.source
      member.active_phone_number!
    end
  end

  private

  def valid_phone_number_for_country
    return if not send_code_phase

    if Phonelib.invalid_for_country?(phone_number, country)
      errors.add :phone_number, :invalid
    end
  end

  def country_code
    country = "CN" if country.blank?
    ISO3166::Country[country].try :country_code
  end

  def save_phone_number
    phone = Phonelib.parse([country_code, phone_number].join)
    member.update phone_number: phone.sanitized.to_s if member.phone_number.blank?
    self.update source: phone.sanitized.to_s
  end

  def gen_code
    self.otp_secret = '%06d' % SecureRandom.random_number(1000000)
    self.refreshed_at = Time.now
  end

  def send_notification
    return if not self.activated_changed?

    if self.activated
      member.notify!('sms_auth_activated')
    else
      member.notify!('sms_auth_deactivated')
    end
  end
end
