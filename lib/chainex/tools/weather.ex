defmodule Chainex.Tools.Weather do
  @moduledoc """
  Weather tool for getting current weather information.

  Note: This is a mock implementation for demonstration purposes.
  In a real application, you would integrate with a weather API.
  """

  alias Chainex.Tool

  @doc """
  Creates a weather tool that can get current weather for a location.
  """
  def new do
    Tool.new(
      name: "get_weather",
      description:
        "Gets current weather information for a specified location including temperature, conditions, humidity, and wind.",
      parameters: %{
        location: %{
          type: :string,
          required: true,
          description:
            "The city and/or country to get weather for (e.g., 'New York', 'London, UK', 'Tokyo, Japan')"
        },
        units: %{
          type: :string,
          default: "celsius",
          enum: ["celsius", "fahrenheit", "kelvin"],
          description: "Temperature units to return"
        }
      },
      function: &get_weather/1
    )
  end

  @doc """
  Gets weather information for a location.

  ## Examples

      iex> Weather.get_weather(%{location: "New York"})
      {:ok, %{temperature: 22, condition: "partly cloudy", humidity: 65, wind: "5 mph SW"}}
  """
  def get_weather(%{location: location, units: units}) do
    # Mock weather data - in real implementation, call weather API
    mock_weather = generate_mock_weather(location, units)
    {:ok, mock_weather}
  end

  def get_weather(%{location: location}) do
    get_weather(%{location: location, units: "celsius"})
  end

  # Generate mock weather data for demonstration
  defp generate_mock_weather(location, units) do
    # Simple hash-based deterministic "weather" for consistency
    location_hash = :erlang.phash2(location, 100)

    base_temp =
      case units do
        # 32-92°F
        "fahrenheit" -> 32 + rem(location_hash, 60)
        # 273-313K  
        "kelvin" -> 273 + rem(location_hash, 40)
        # -5 to 30°C
        _ -> rem(location_hash, 35) - 5
      end

    conditions = [
      "sunny",
      "partly cloudy",
      "cloudy",
      "light rain",
      "heavy rain",
      "snow",
      "fog",
      "windy",
      "stormy"
    ]

    condition = Enum.at(conditions, rem(location_hash, length(conditions)))

    # 30-80%
    humidity = 30 + rem(location_hash * 2, 50)
    # 0-19 mph
    wind_speed = rem(location_hash * 3, 20)

    wind_directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    wind_dir = Enum.at(wind_directions, rem(location_hash, length(wind_directions)))

    temp_suffix =
      case units do
        "fahrenheit" -> "°F"
        "kelvin" -> "K"
        _ -> "°C"
      end

    %{
      location: location,
      temperature: "#{base_temp}#{temp_suffix}",
      condition: condition,
      humidity: "#{humidity}%",
      wind: "#{wind_speed} mph #{wind_dir}",
      last_updated: DateTime.utc_now() |> DateTime.to_string()
    }
  end
end
