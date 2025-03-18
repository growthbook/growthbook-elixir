defmodule GrowthBook.DecryptionUtils do
  @moduledoc """
  Utilities for decrypting encrypted features from GrowthBook API.
  Uses AES-CBC with PKCS7 padding.
  """

  require Logger

  @doc """
  Decrypts an encrypted payload using the provided decryption key.

  The payload should be in the format "iv.ciphertext" where both parts are base64 encoded.
  Returns {:ok, decrypted_string} on success or {:error, reason} on failure.
  """
  @spec decrypt(binary() | String.t(), binary() | String.t()) ::
          {:ok, binary()} | {:error, String.t()}
  def decrypt(payload, decryption_key) when is_binary(payload) and is_binary(decryption_key) do
    with {:ok, {iv, cipher_text}} <- split_payload(payload),
         {:ok, decoded_iv} <- decode_base64(iv),
         {:ok, decoded_cipher} <- decode_base64(cipher_text),
         {:ok, key} <- create_key(decryption_key),
         {:ok, plain_text} <- do_decrypt(decoded_cipher, key, decoded_iv),
         {:ok, valid_text} <- validate_utf8(plain_text) do
      {:ok, valid_text}
    else
      {:error, reason} ->
        Logger.error("Decryption failed: #{reason}")
        {:error, reason}
    end
  end

  # Ensure we're always working with binaries
  def decrypt(payload, decryption_key) when is_binary(payload) do
    decrypt(payload, to_string(decryption_key))
  end

  def decrypt(payload, decryption_key) when is_binary(decryption_key) do
    decrypt(to_string(payload), decryption_key)
  end

  def decrypt(payload, decryption_key) do
    decrypt(to_string(payload), to_string(decryption_key))
  end

  @spec split_payload(binary()) :: {:ok, {binary(), binary()}} | {:error, String.t()}
  defp split_payload(payload) do
    case String.split(payload, ".", parts: 2) do
      [iv, cipher_text] -> {:ok, {iv, cipher_text}}
      _ -> {:error, "Invalid payload format"}
    end
  end

  @spec decode_base64(binary()) :: {:ok, binary()} | {:error, String.t()}
  defp decode_base64(string) do
    try do
      {:ok, Base.decode64!(string)}
    rescue
      _ -> {:error, "Invalid base64 encoding"}
    end
  end

  @spec create_key(binary()) :: {:ok, binary()} | {:error, String.t()}
  defp create_key(decryption_key) do
    try do
      # Direct Base64 decoding without converting to char list
      {:ok, Base.decode64!(decryption_key)}
    rescue
      e in ArgumentError ->
        Logger.error("Invalid decryption key: #{Exception.message(e)}")
        {:error, "Invalid decryption key"}

      _ ->
        {:error, "Invalid decryption key"}
    end
  end

  @spec do_decrypt(binary(), binary(), binary()) :: {:ok, binary()} | {:error, String.t()}
  defp do_decrypt(cipher_text, key, iv) do
    try do
      plain_text = :crypto.crypto_one_time(:aes_cbc, key, iv, cipher_text, false)
      # Remove PKCS7 padding
      unpadded = unpad_pkcs7(plain_text)
      {:ok, unpadded}
    rescue
      e ->
        Logger.error("Decryption failed: #{Exception.message(e)}")
        {:error, "Decryption failed"}
    end
  end

  @spec validate_utf8(binary()) :: {:ok, binary()} | {:error, String.t()}
  defp validate_utf8(text) do
    if String.valid?(text) do
      {:ok, text}
    else
      {:error, "Invalid UTF-8 encoding"}
    end
  end

  @spec unpad_pkcs7(binary()) :: binary()
  defp unpad_pkcs7(data) do
    # Get the last byte which contains the padding length
    padding_length = :binary.last(data)

    # Remove the padding
    binary_part(data, 0, byte_size(data) - padding_length)
  end
end
