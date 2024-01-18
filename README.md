# tasmota_berry_pid

This is a Berry Script to regulate a Wine Cooler Temperature using a PID controller.

This is the cooler: https://loja.electrolux.com.br/adega-elctrolux--8-garrafas-1-porta-preta-acabamento-em-aluminio---acb08-/p?idsku=310118741&amp;utm_source=google&amp;utm_campaign=googlepla&amp;utm_medium=shopping&amp;gclid=CjwKCAjwl6OiBhA2EiwAuUwWZblqWcRMnEFmYsLsG8LWJ7mZvVhUz-GGubBmveTbVgpU_DQ_GiCKHBoC1JoQAvD_BwE, which contains a very unreliable control board that always stop working 12 months after bought, maximum. This way, its better to do a better one myself that buying a replacement.

The cooler is peltier based and uses 3 relays. One turns on the peltier, one controls the hot side cooler and the last controls the cold side cooler.

The hardware is ESP32 Based and runs, at time of writing, stock Tasmota 13.3.0. The complete hardware schematics for the system can be found at https://github.com/glmoritz/wine_cooler


