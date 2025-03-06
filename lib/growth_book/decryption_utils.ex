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
  @spec decrypt(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def decrypt(payload, decryption_key) do
    with {:ok, {iv, cipher_text}} <- split_payload(payload),
         {:ok, decoded_iv} <- decode_base64(iv),
         {:ok, decoded_cipher} <- decode_base64(cipher_text),
         {:ok, key} <- create_key(decryption_key),
         {:ok, plain_text} <- do_decrypt(decoded_cipher, key, decoded_iv),
         {:ok, _} <- validate_utf8(plain_text) do
      {:ok, plain_text}
    else
      {:error, reason} ->
        Logger.error("Decryption failed: #{reason}")
        {:error, reason}
    end
  end

  defp split_payload(payload) do
    case String.split(payload, ".", parts: 2) do
      [iv, cipher_text] -> {:ok, {iv, cipher_text}}
      _ -> {:error, "Invalid payload format"}
    end
  end

  defp decode_base64(string) do
    try do
      {:ok, Base.decode64!(string)}
    rescue
      _ -> {:error, "Invalid base64 encoding"}
    end
  end

  defp create_key(decryption_key) do
    try do
      key =
        decryption_key
        |> String.to_charlist()
        |> Base.decode64!()

      {:ok, key}
    rescue
      _ -> {:error, "Invalid decryption key"}
    end
  end

  defp do_decrypt(cipher_text, key, iv) do
    try do
      plain_text = :crypto.crypto_one_time(:aes_cbc, key, iv, cipher_text, false)
      unpadded = unpad_pkcs7(plain_text)
      {:ok, unpadded}
    rescue
      _ -> {:error, "Decryption failed"}
    end
  end

  defp validate_utf8(text) do
    case String.valid?(text) do
      true -> {:ok, text}
      false -> {:error, "Invalid UTF-8 encoding"}
    end
  end

  # PKCS7 unpadding
  defp unpad_pkcs7(data) do
    padding_length = :binary.last(data)
    binary_part(data, 0, byte_size(data) - padding_length)
  end
end
