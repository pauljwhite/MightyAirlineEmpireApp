import '../models/models.dart';

int _v(int seed, int count) => seed.abs() % count;

NewsArticle generateRouteArticle({
  required String id,
  required String airlineName,
  required String originIata,
  required String destIata,
  required double distanceKm,
  required int gameDay,
  required int seed,
}) {
  final route = '$originIata–$destIata';
  final isLongHaul = distanceKm > 4500;
  final isMedium = distanceKm > 1500 && !isLongHaul;
  final distLabel = isLongHaul
      ? '${(distanceKm / 1000).toStringAsFixed(1)}-thousand-kilometre'
      : isMedium
      ? 'medium-haul'
      : 'short-haul';

  switch (_v(seed, 5)) {
    case 0:
      return NewsArticle(
        id: id,
        headline: '$airlineName opens $route service',
        subheadline:
            'Carrier launches $distLabel scheduled operations between the two cities',
        paragraphs: [
          '$airlineName has inaugurated scheduled passenger services on the $route corridor, adding a new connection between the two airport pairs. The route, which covers approximately ${distanceKm.round()} kilometres, will be served with multiple weekly frequencies from the outset.',
          'The carrier cited sustained unmet demand and a gap in the direct point-to-point schedule as the primary commercial rationale. Revenue management modelling indicated sufficient yield to support the route without reliance on onward connecting traffic, which the airline described as a favourable indicator of organic demand strength.',
          'Rival operators serving the same city pairing through one-stop routings acknowledged the new competitor entry but declined to comment on whether they would adjust pricing in response. Analysts expect load factors on the sector to stabilise within the first quarter of operation as the market calibrates to the additional seat supply.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 1:
      return NewsArticle(
        id: id,
        headline: '$airlineName enters $route market',
        subheadline:
            'Carrier challenges incumbents on a route previously dominated by a single operator',
        paragraphs: [
          '$airlineName has entered the $route market, becoming the second carrier to offer direct services on a pairing that had until now been the exclusive preserve of a single competitor. The move is the latest in a series of capacity deployments aimed at diversifying the airline\'s route map beyond its core network.',
          'Industry observers noted that the origin-destination yield data for the sector has been unusually strong in recent periods, creating an attractive entry signal. The newcomer is expected to price aggressively in the opening weeks to stimulate trial, before adjusting to a sustainable yield position once an initial passenger base has been established.',
          'The incumbent operator has not yet announced whether it will respond with additional capacity or promotional fares. Market share shifts on newly contested routes of this type typically take two to three scheduling seasons to stabilise, with the outcome often determined by frequency rather than price alone.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 2:
      return NewsArticle(
        id: id,
        headline: '$airlineName adds $route to summer schedule',
        subheadline:
            'High-demand corridor included in seasonal capacity expansion',
        paragraphs: [
          '$airlineName has confirmed the addition of $route to its seasonal schedule, citing strong forward booking indicators as justification for the capacity commitment. The route will form part of a broader network expansion the carrier is undertaking across several high-yield point-to-point corridors.',
          'Load factor projections prepared by the airline\'s network planning team show a breakeven occupancy rate achievable within the first operating month at current market fares. The carrier indicated it has secured advantageous slot timings at both airports, which are expected to attract business-sensitive travellers.',
          'The announcement was welcomed by regional tourism bodies and business groups at both ends of the route, who have campaigned for improved air connectivity. Economic studies cited in industry submissions estimate that a new direct air link of this type typically generates between three and five times its own direct revenue in downstream hospitality and commerce activity.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 3:
      return NewsArticle(
        id: id,
        headline:
            isLongHaul
                ? '$airlineName announces first long-haul service to $destIata'
                : '$airlineName expands regional reach with $route launch',
        subheadline:
            isLongHaul
                ? 'New intercontinental route marks a strategic milestone for the carrier'
                : 'Regional network deepened as carrier targets underserved secondary market',
        paragraphs: [
          isLongHaul
              ? '$airlineName has announced the launch of its first long-haul service to $destIata, marking a significant milestone in the carrier\'s strategic evolution from a predominantly short and medium-haul operator. The route, operated at distances exceeding ${(distanceKm / 1000).toStringAsFixed(0)} thousand kilometres, represents a fundamental shift in fleet utilisation philosophy.'
              : '$airlineName has deepened its regional network with the addition of $route, targeting a market characterised by high frequency demand and limited current direct competition. The route fits the carrier\'s stated strategy of building point-to-point density in markets underserved by the hub-and-spoke networks of larger competitors.',
          isLongHaul
              ? 'The decision to launch the service reflects confidence in the long-haul leisure and visiting-friends-and-relatives segments, which have shown resilience to fare increases in recent booking cycles. The airline noted that premium cabin load factors on comparable long-haul routes operated by peer carriers have been running above historical averages, providing commercial support for the investment in widebody capacity.'
              : 'The move reflects a growing trend among mid-sized carriers to prioritise slot efficiency at secondary airports where congestion charges and handling costs are structurally lower. Modelling prepared by the carrier\'s commercial team suggests the route can sustain profitability at load factors as low as fifty-eight percent, a threshold management described as highly achievable given current booking pace.',
          'The carrier has indicated it will review performance at the end of the initial operating period before committing to year-round scheduling, with a decision on permanent inclusion in the permanent schedule expected within six months of the first revenue departure.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    default:
      return NewsArticle(
        id: id,
        headline: '$airlineName launches $distLabel $route operations',
        subheadline:
            'Network development team cites favourable yield environment as trigger for deployment',
        paragraphs: [
          '$airlineName has launched new scheduled services on the $route city pair, adding direct connectivity on a route covering approximately ${distanceKm.round()} kilometres. The carrier cited a combination of strong unmet demand and a favourable competitive environment as the commercial basis for the launch.',
          'The frequency and timing of the services were negotiated with both airport authorities over the preceding months. Both origin and destination airports have confirmed the allocation of suitable slots, with turnaround times structured to support onward connections within each carrier\'s respective hub network where applicable.',
          'Revenue management officials at the airline said pricing on the new route will be managed dynamically from the outset using the same yield optimisation systems deployed across the existing network, with no introductory discount period planned beyond standard promotional fares available at time of booking.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
  }
}

NewsArticle generateNewEntrantArticle({
  required String id,
  required String airlineName,
  required String hubIata,
  required String hubCity,
  required int gameDay,
  required int seed,
}) {
  final hub = hubCity.isNotEmpty ? hubCity : hubIata;

  switch (_v(seed, 4)) {
    case 0:
      return NewsArticle(
        id: id,
        headline: 'New carrier $airlineName launches at $hubIata',
        subheadline:
            'Investor-backed start-up targets underserved markets from $hub base',
        paragraphs: [
          '$airlineName has commenced operations from its inaugural hub at $hubIata, becoming the latest carrier to enter the commercial aviation market. The airline, backed by a consortium of private investors, has secured its air operator certificate following a regulatory review period of approximately twelve months.',
          'The carrier\'s founding management team includes several executives drawn from established network and low-cost carriers, providing operational credibility. Initial fleet composition is expected to be lean by design, with the airline stating that capital discipline and route selectivity will be central to its launch strategy.',
          'Industry analysts cautioned that the current fuel and yield environment presents meaningful headwinds for new entrants, while acknowledging that $hub offers structural advantages including available slots and competitive ground handling costs. The carrier has declined to disclose specific route intentions ahead of its scheduled timetable publication.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 1:
      return NewsArticle(
        id: id,
        headline: '$airlineName enters market with $hub hub launch',
        subheadline:
            'Carrier positions itself as challenger to established players on key corridors',
        paragraphs: [
          '$airlineName has begun revenue flying from its home base at $hubIata, entering a market already served by multiple established carriers. The airline\'s chief executive described the entry as the result of a two-year analysis of demand patterns that identified structural overcapacity in some sectors and underservice in others.',
          'The launch timing is deliberate: booking data available to the carrier\'s network team suggests that several routes from $hub are priced above sustainable long-run equilibrium, creating a viable entry opportunity. The carrier has signalled it will price competitively without engaging in the below-cost selling that has characterised some start-up failures.',
          'Pilot recruitment has been completed for the initial phase, with the carrier drawing on experienced crews from markets where recent airline consolidations have created a supply of available licenced flight crew. The airline expects to reach operational breakeven within its first year if load factors meet modelled projections.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 2:
      return NewsArticle(
        id: id,
        headline: 'Charter-turned-scheduled carrier $airlineName debuts at $hubIata',
        subheadline:
            'Former leisure specialist pivots to scheduled operations from $hub base',
        paragraphs: [
          '$airlineName has transitioned from charter and leisure operations to the scheduled aviation market, launching its first point-to-point timetabled services from $hubIata. The carrier cited maturation in the packaged-holiday segment and improved demand transparency in the direct-booking market as the strategic rationale.',
          'The conversion from charter to scheduled operator required a revised air operator certificate and the adoption of new ticketing, reservation and distribution infrastructure. The airline spent the preceding period overhauling its commercial systems to meet the requirements of scheduled operations, including real-time pricing and interline connectivity.',
          'Management acknowledged that entering the scheduled market entails a different risk profile than charter flying, where revenue is largely guaranteed through tour operator block agreements. The carrier expressed confidence that its lower cost base relative to legacy scheduled carriers provides a sustainable competitive position.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    default:
      return NewsArticle(
        id: id,
        headline: 'Aviation market gains new entrant: $airlineName',
        subheadline:
            'Newly certificated carrier establishes initial base at $hubIata',
        paragraphs: [
          'The commercial aviation industry has gained a new carrier with the launch of $airlineName, which has established its operating base at $hubIata. The airline received its air operator certificate following compliance inspections by the national aviation authority and has completed wet-lease arrangements to underpin its initial flying programme.',
          'The founding team has articulated a strategy focused on route markets displaying consistent year-on-year demand growth with limited current direct competition. Rather than attempting to enter congested hub-to-hub markets from the outset, the carrier intends to build a sustainable point-to-point operation that generates positive cash flow before pursuing aggressive expansion.',
          'Independent analysts viewed the launch with cautious optimism, noting that recent periods have seen elevated airline failures alongside new entrant activity. Survival rates for new carriers improve substantially when launch capitalisation exceeds eighteen months of operating expenditure — a threshold the airline\'s backers have committed to meeting.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
  }
}

NewsArticle generateInsolvencyArticle({
  required String id,
  required String airlineName,
  required int gameDay,
  required int seed,
}) {
  switch (_v(seed, 4)) {
    case 0:
      return NewsArticle(
        id: id,
        headline: '$airlineName enters insolvency protection',
        subheadline:
            'Carrier cites unsustainable fuel costs and declining yields as primary causes',
        paragraphs: [
          '$airlineName has filed for insolvency protection after sustained operating losses rendered the carrier unable to service its financial obligations. The airline cited the combined impact of elevated fuel expenditure — which had risen to represent an unsustainable proportion of total operating costs — and persistent yield pressure across its core route network.',
          'Load factors on several of the carrier\'s highest-cost routes had been running below breakeven for multiple consecutive quarters. Attempts to raise average fares met with demand elasticity that accelerated the traffic decline, creating a spiral in which unit revenue deterioration outpaced management\'s ability to reduce the cost base through schedule reductions.',
          'Administrators appointed by the court have indicated that the airline\'s route slots and brand may attract interest from competitor carriers and infrastructure funds. Operations will continue in the short term while options are assessed, though creditors including aircraft lessors have signalled they expect an accelerated resolution process.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 1:
      return NewsArticle(
        id: id,
        headline: '$airlineName collapses under weight of overcapacity losses',
        subheadline:
            'Yield environment deteriorated beyond recovery as competition intensified',
        paragraphs: [
          '$airlineName has entered administration following a period of accelerating financial deterioration driven by overcapacity in its primary markets. The carrier had maintained ambitious capacity growth despite evidence that market yields were under structural pressure, a strategy that left insufficient cash reserves when load factor expectations failed to materialise.',
          'Internal communications reviewed by industry sources indicate that the airline\'s board received multiple warnings from its treasury function about liquidity headroom in the preceding six months. A proposed emergency recapitalisation that would have required existing shareholders to contribute additional equity did not secure sufficient support before the cash position became critical.',
          'The insolvency is expected to provide some yield relief to surviving competitors, several of whom have already indicated their interest in wet-leasing grounded aircraft from the administration estate and redeploying them on routes where capacity will be absorbed by the market.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 2:
      return NewsArticle(
        id: id,
        headline: 'Creditors force $airlineName into administration',
        subheadline:
            'Aircraft lessors move to recover assets after missed lease payments',
        paragraphs: [
          '$airlineName has been placed into administration following action by a syndicate of aircraft lessors who moved to recover their assets after the airline defaulted on a series of monthly lease payment obligations. The carrier had been in restructuring discussions with its creditor group for several months, but was unable to agree terms that satisfied all parties.',
          'The lessor action crystallised a broader liquidity crisis: the loss of confidence among fuel suppliers and ground handling providers, who had been operating on reduced credit terms, resulted in a withdrawal of services that made continued flying untenable within forty-eight hours of the first lessor filing.',
          'Staff and passengers have been left in an uncertain position. Aviation consumer protection bodies are working with the insolvency practitioners to identify alternative carriers prepared to honour outstanding tickets at face value, though no commitments have been made. Employees have been advised to register as preferential creditors in the administration process.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    default:
      return NewsArticle(
        id: id,
        headline: '$airlineName files for insolvency protection',
        subheadline:
            'Liquidity crisis ends months of speculation over carrier\'s viability',
        paragraphs: [
          '$airlineName has confirmed it has filed for insolvency protection, ending a prolonged period of market speculation about the carrier\'s financial position. The airline had been the subject of analyst downgrades and creditor concern for several quarters, with its cash reserves falling below the threshold typically required to sustain forward operations.',
          'A last-ditch attempt to secure a strategic investor willing to inject equity capital in exchange for a controlling stake did not produce a binding offer within the timeframe set by the board. Advisers working on the transaction said terms that would have provided adequate protection for the airline\'s existing debt holders could not be reconciled with the pricing requirements of prospective acquirors.',
          'National aviation authorities have confirmed that $airlineName\'s air operator certificate remains valid in the immediate term while the administration process determines the outcome for the business. Regulators have indicated they will move quickly to revoke the certificate if operations cannot be sustained on a financially responsible basis.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
  }
}

NewsArticle generateRouteTerminationArticle({
  required String id,
  required String airlineName,
  required int gameDay,
  required int seed,
}) {
  switch (_v(seed, 4)) {
    case 0:
      return NewsArticle(
        id: id,
        headline: '$airlineName cuts loss-making route from schedule',
        subheadline:
            'Carrier culls underperforming sector as capacity rationalisation continues',
        paragraphs: [
          '$airlineName has withdrawn services on an underperforming route following a network review that concluded the sector was not viable at current load factors and prevailing yield levels. The airline indicated the decision was taken after a minimum operating period during which remediation measures including fare adjustments and frequency reductions failed to return the route to profitability.',
          'The airline\'s network planning team reported that the route had been consuming disproportionate operational resources relative to its revenue contribution, and that redeploying the capacity to higher-performing sectors would deliver a measurable improvement in overall network margin.',
          'Passengers booked on the discontinued services have been offered full refunds or rebooking on alternative routings. The carrier stated that the termination does not reflect a strategic exit from either market, and that the route will remain under periodic review for potential re-entry if demand conditions change.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 1:
      return NewsArticle(
        id: id,
        headline: '$airlineName suspends route amid yield deterioration',
        subheadline:
            'Intense competition from rival carriers eroded margins below sustainable levels',
        paragraphs: [
          '$airlineName has suspended operations on a route where yield deterioration driven by aggressive competitor pricing made continued flying financially untenable. The carrier\'s revenue management team had been monitoring the sector closely over recent periods and concluded that the competitive dynamic had shifted structurally rather than cyclically.',
          'The airline noted that rivals had added substantial seat supply on the same or closely parallel routings, compressing the average market fare to a level at which the carrier could not operate without generating per-departure losses. Internal analysis concluded that the most commercially rational course was to redeploy aircraft to routes where the carrier\'s cost base represented a genuine competitive advantage.',
          'The withdrawal is framed by management as a disciplined commercial decision rather than a retreat, with the airline committing to monitor the market and re-enter if competitive dynamics return to more favourable equilibrium. Slot pairs at both airports have been retained where possible to preserve the option of resumption.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 2:
      return NewsArticle(
        id: id,
        headline: 'Fleet constraints force $airlineName to cut route',
        subheadline:
            'Maintenance obligations reduce available aircraft, prompting network pruning',
        paragraphs: [
          '$airlineName has terminated services on one of its scheduled routes as a result of fleet availability constraints stemming from a higher-than-anticipated volume of aircraft entering scheduled maintenance input. The reduction in serviceable aircraft has forced the carrier to prioritise its highest-margin services, with lower-performing routes deferred or terminated.',
          'The airline\'s technical operations department indicated that several airframes had accumulated flight hours at a faster rate than projected, bringing forward scheduled maintenance events that would otherwise have been deferred to later in the year. The adjustment compressed the available fleet to a point where not all published routes could be operated at planned frequencies.',
          '$airlineName said it expected the fleet availability position to normalise once the current maintenance backlog had been cleared, and that the timing and terms of any route restoration would be assessed at that point based on prevailing market conditions.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    default:
      return NewsArticle(
        id: id,
        headline: '$airlineName announces route withdrawal',
        subheadline:
            'Sector removed from forward schedule following strategic network review',
        paragraphs: [
          '$airlineName has announced the withdrawal of a route from its scheduled network following a comprehensive review of route economics conducted by its commercial division. The airline said the decision reflected a disciplined approach to network management in which each route must demonstrate a credible path to sustained profitability within a defined operating period.',
          'The carrier\'s chief commercial officer said the withdrawal was consistent with the airline\'s strategy of concentrating capacity on routes where it holds structural advantages in terms of frequency, connectivity, or cost. Routes that do not meet the carrier\'s required return threshold are subject to periodic review and are withdrawn when remediation is not achievable within the planning horizon.',
          'The airline has confirmed that all affected passengers will receive notification and will be offered full refunds or rebooking on the next available service. The slot allocation at both airports will be reviewed in the context of the carrier\'s upcoming scheduling submission.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
  }
}

NewsArticle generateAcquisitionArticle({
  required String id,
  required String buyerName,
  required String targetName,
  required int gameDay,
  required int seed,
}) {
  switch (_v(seed, 4)) {
    case 0:
      return NewsArticle(
        id: id,
        headline: '$buyerName acquires $targetName in consolidation move',
        subheadline:
            'Deal creates enlarged network with combined fleet and route authority',
        paragraphs: [
          '$buyerName has completed the acquisition of $targetName, creating a larger combined carrier with access to the target\'s route authorities, slot portfolio and aircraft fleet. The transaction, which has been the subject of regulatory review, received clearance subject to conditions that preserve competitive access on a small number of overlapping routes.',
          'The acquiring carrier\'s chief executive described the deal as strategically transformative, citing the complementary geographic coverage of the two networks as the primary value driver. Where the two carriers previously competed on certain sectors, the combined entity is expected to rationalise frequency and pricing in a manner that improves overall network yield.',
          'Former $targetName employees will be integrated into $buyerName\'s operational structure under terms agreed with labour representatives. Aircraft from the acquired fleet that meet current operational requirements will be absorbed into the combined fleet plan; older types will be assessed for early return or sale.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 1:
      return NewsArticle(
        id: id,
        headline: '$buyerName eliminates rival with purchase of $targetName',
        subheadline:
            'Market consolidation accelerates as larger carriers absorb weaker competitors',
        paragraphs: [
          '$buyerName has purchased $targetName, removing a direct competitor from several key routes and materially improving its position in those markets. The acquisition is the latest evidence of a consolidation trend in which carriers with strong balance sheets are acquiring distressed or subscale competitors before they exit through insolvency.',
          'The purchase price reflects a premium to $targetName\'s standalone asset value, justified by the buyer on the basis of the route authorities and bilateral traffic rights that transfer with the carrier\'s operating certificate. In several markets where the two carriers were in direct competition, the combined entity will now hold a dominant position that is expected to support higher sustainable yields.',
          'Regulators examined the transaction carefully in light of competition concerns on overlapping routes. The conditions attached to the clearance decision require the combined entity to make slots available to new entrants on specified sectors for a period of three years, a requirement that $buyerName described as manageable and unlikely to materially affect the commercial rationale.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 2:
      return NewsArticle(
        id: id,
        headline: '$buyerName rescues $targetName with takeover bid',
        subheadline:
            'Distressed carrier saved from administration by rival\'s opportunistic acquisition',
        paragraphs: [
          '$buyerName has completed the acquisition of $targetName, rescuing the carrier from an imminent administration that would have grounded its fleet and left passengers and creditors without recourse. The deal was structured as an accelerated acquisition of the business and assets, bypassing a conventional sale process given the urgency of the carrier\'s financial position.',
          'The rescue preserves jobs and continuity of service on routes where $targetName had been the sole direct operator, outcomes that both the acquiring carrier and aviation regulators cited as important objectives in facilitating a swift transaction. Passengers holding forward bookings have been assured their tickets will be honoured.',
          '$buyerName has indicated it will take a period of several months to fully integrate the acquired operation, during which the $targetName brand may continue in use. Longer-term branding decisions will be made once the network integration plan has been finalised and the commercial case for maintaining a dual-brand strategy has been assessed.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    default:
      return NewsArticle(
        id: id,
        headline: 'ACQUISITION: $buyerName takes over $targetName',
        subheadline:
            'Strategic deal reshapes competitive landscape across overlapping networks',
        paragraphs: [
          '$buyerName has announced and completed the acquisition of $targetName, a transaction that reshapes the competitive structure of the markets in which both carriers operate. The merged entity will combine the route networks, fleet resources and commercial agreements of both carriers under unified management.',
          'The deal\'s terms were not disclosed in full, but sources with knowledge of the transaction indicated that the consideration reflected both the tangible asset value of $targetName\'s fleet and the intangible value of its traffic rights, frequent flyer liabilities and ground infrastructure agreements. The acquiring carrier financed the purchase primarily from existing cash reserves.',
          'Integration planning has been underway since the letter of intent was signed, and management expect the operational consolidation — including crew rostering, maintenance scheduling and network optimisation — to be largely complete within twelve months. Revenue synergies are expected to exceed cost savings over the medium term.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
  }
}

NewsArticle generateDissolutionArticle({
  required String id,
  required String airlineName,
  required int gameDay,
  required int seed,
}) {
  switch (_v(seed, 3)) {
    case 0:
      return NewsArticle(
        id: id,
        headline: '$airlineName ceases operations permanently',
        subheadline:
            'Failed restructuring leaves airline with no viable path to recovery',
        paragraphs: [
          '$airlineName has ceased all commercial operations and is to be formally dissolved following the failure of a restructuring process that had aimed to return the carrier to financial viability. The decision to discontinue the business was taken by administrators after it became clear that no acquiror was willing to proceed on terms that would have covered the carrier\'s residual liabilities.',
          'All flights have been grounded with immediate effect. Passengers holding tickets have been directed to contact their booking agents or credit card providers to pursue refund claims. The airline\'s air operator certificate will be surrendered, ending its operational existence.',
          'The collapse marks the end of a carrier that at various points in its operating history had been a notable player in its domestic and regional markets. Industry analysts cited a combination of high fixed costs, an ageing fleet and failure to adapt pricing strategy to a changing competitive environment as the structural factors that ultimately proved fatal.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    case 1:
      return NewsArticle(
        id: id,
        headline: 'Liquidators wind up $airlineName after administration failure',
        subheadline:
            'Asset sales to proceed as no buyer emerges for the going concern',
        paragraphs: [
          'The administration of $airlineName has been converted to a liquidation after the court-appointed administrators concluded that no viable purchaser could be found for the airline as a going concern. The business will be wound up in an orderly manner, with aircraft returned to lessors and other assets sold to the highest bidder.',
          'Staff have been formally notified of redundancy. Union representatives expressed disappointment that the administration process had not produced a rescue outcome, particularly given that interest from potential buyers had been reported in the early weeks of the administration. Those discussions ultimately did not produce binding offers.',
          'Slot pairs held by the airline at congested airports will be redistributed through the relevant slot coordination process, with competing carriers expected to apply for the resulting availability. The reallocation is expected to take several scheduling seasons to work through, leaving some markets temporarily underserved.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
    default:
      return NewsArticle(
        id: id,
        headline: '$airlineName dissolved after prolonged insolvency',
        subheadline:
            'Carrier formally wound up after inability to sustain operations',
        paragraphs: [
          '$airlineName has been formally dissolved following a period of prolonged insolvency during which it was unable to resume commercial operations. The carrier had been in a suspended state since the appointment of administrators, with no rescue transaction materialising within the period during which its operating infrastructure could be preserved.',
          'The winding-up order brings to a close a process that had generated considerable uncertainty for the airline\'s employees, creditors and remaining customers. Claims will be processed through the standard insolvency priority hierarchy, with secured creditors — primarily aircraft lessors and fuel suppliers — expected to recover the largest proportion of their outstanding obligations.',
          'Regulators have archived the airline\'s operating certificate and route authorities. The carrier\'s IATA designator code has been returned to the allocation pool and may be reassigned to a future operator after a standard moratorium period.',
        ],
        severity: 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
  }
}

/// Generates a detailed news article for a fleet technical event
/// (engine fault, hydraulic issue, bird strike, etc.) on an AI aircraft.
///
/// [faultLabel] is the raw event label, e.g. 'engine fault', 'bird strike'.
/// [aircraftName] is the registration/name, e.g. 'B737 EA-123'.
/// [routeLabel] is e.g. 'LHR-JFK' or 'unassigned services'.
/// [grounds] indicates whether the aircraft was taken out of service.
NewsArticle generateFleetEventArticle({
  required String id,
  required String airlineName,
  required String aircraftName,
  required String faultLabel,
  required String routeLabel,
  required bool grounds,
  required int gameDay,
  required int seed,
}) {
  switch (faultLabel) {
    case 'engine fault':
      return NewsArticle(
        id: id,
        headline: '$airlineName aircraft pulled from service after engine fault',
        subheadline: '$aircraftName reported abnormal engine indications on $routeLabel service',
        paragraphs: [
          '$airlineName has withdrawn $aircraftName from scheduled operations after the aircraft reported abnormal engine performance indications during its $routeLabel service. The crew elected to discontinue operations in accordance with standard abnormal procedures, and the aircraft was ferried to its maintenance base under reduced-thrust precautionary conditions.',
          'Technical teams have begun borescope inspections of the high-pressure turbine section and have called in the engine manufacturer\'s field support unit. The airline stated that the precautionary grounding is consistent with its safety management procedures, which mandate withdrawal from service on any abnormal powerplant indication pending engineering assessment.',
          grounds
              ? '$airlineName expects to have a full assessment within 48 hours. The carrier is sourcing replacement capacity to cover affected $routeLabel services during the inspection period.'
              : 'Engineers cleared the aircraft to resume operations following a ground run and borescope inspection. An additional maintenance item has been logged for resolution at the aircraft\'s next scheduled heavy check.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'hydraulic issue':
      return NewsArticle(
        id: id,
        headline: '$airlineName grounds $aircraftName over hydraulic fault',
        subheadline: 'Pressure anomaly detected in primary hydraulic system on $routeLabel operation',
        paragraphs: [
          '$airlineName has grounded $aircraftName after technicians identified an anomalous pressure reading in the aircraft\'s primary hydraulic system during a post-flight inspection following the $routeLabel sector. The fault was not reported during the flight itself, but was detected during routine system health monitoring at turnround.',
          'Engineering staff have traced the fault to a suspected leak in the hydraulic line serving the nose gear actuation circuit. The aircraft has been positioned in the maintenance hangar and all three hydraulic systems are undergoing full functional testing before the airline will consider a return to service.',
          grounds
              ? 'The carrier confirmed that no safety event occurred on the affected service, and that the discovery of the defect through post-flight monitoring reflects the effectiveness of its condition-monitoring programme.'
              : 'Following a successful ground hydraulic test and actuation cycling, the aircraft has been returned to service with an enhanced monitoring schedule for the affected circuit.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'fuselage crack':
      return NewsArticle(
        id: id,
        headline: '$airlineName takes $aircraftName offline after structural finding',
        subheadline: 'Fatigue indication found in fuselage skin during scheduled inspection',
        paragraphs: [
          '$airlineName has removed $aircraftName from active service following the discovery of a hairline fatigue crack in the fuselage skin during a scheduled airframe inspection. The finding is described as a typical high-cycle fatigue indication in the skin panel adjacent to the forward door frame, an area known to accumulate cyclic stress with pressurisation.',
          'The airline\'s structural engineering team has notified the aircraft manufacturer and the national airworthiness authority in line with mandatory defect-reporting obligations. A repair scheme using standard doubler-plate methodology has been submitted for airworthiness approval.',
          'The airframe had accumulated a high number of pressurisation cycles relative to its age, which engineering sources noted is not unusual for an aircraft operated predominantly on short-sector routes. No similar findings have been reported on other aircraft in the carrier\'s fleet from the same structural inspection batch.',
        ],
        severity: 'grounding',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'avionics fault':
      return NewsArticle(
        id: id,
        headline: '$airlineName reports avionics anomaly on $aircraftName',
        subheadline: 'Flight management system irregularity detected during $routeLabel sector',
        paragraphs: [
          '$airlineName has reported an avionics anomaly on $aircraftName after the flight crew observed an unexpected flight management system alert during the $routeLabel sector. The crew completed the applicable non-normal checklist and the aircraft arrived at its destination without further incident, but post-flight review of the onboard maintenance system flagged a latent fault code requiring engineering investigation.',
          grounds
              ? 'The aircraft has been taken out of service pending a full avionics software and hardware diagnostic. Avionics technicians are working with the line-replaceable-unit\'s original equipment manufacturer to isolate the fault to a specific module.'
              : 'Following a ground software reset and LRU substitution test, engineers isolated the fault to a single navigation data processor module, which has been replaced. The aircraft has been returned to service after a satisfactory avionics health check.',
          'The carrier reported the defect to the manufacturer\'s technical support centre and to the national authority in accordance with mandatory occurrence reporting procedures. No safety impact was assessed for the affected sector.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'fuel leak':
      return NewsArticle(
        id: id,
        headline: '$airlineName $aircraftName grounded after fuel system defect',
        subheadline: 'Leak detected in wing tank fuel line following $routeLabel service',
        paragraphs: [
          '$airlineName has taken $aircraftName out of service following the discovery of a fuel leak in the wing tank feed line during a post-flight walk-around inspection after the $routeLabel service. Ground crew observed a seeping fuel stain on the underside of the left wing, and the aircraft was immediately isolated and depressurised as a precautionary measure.',
          'Fuel system engineers have identified the leak source as a fractured fuel line fitting in the tank collector cell, consistent with a fatigue failure of the coupling thread under thermal cycling loads. The repair requires access through the wing inspection panel, and the aircraft has been positioned in the hangar for fuel system work.',
          grounds
              ? 'The carrier stated that the amount of fuel lost was below the safety-significant threshold and that the crew\'s pre-departure fuel checks were within normal parameters throughout the flight.'
              : 'Engineers repaired the coupling and conducted a pressure test and leak check before returning the aircraft to service. The repair has been logged with the manufacturer.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'pressurisation fault':
      return NewsArticle(
        id: id,
        headline: '$airlineName $aircraftName removed from service after cabin pressure event',
        subheadline: 'Automatic pressurisation controller triggered precautionary descent on $routeLabel',
        paragraphs: [
          '$airlineName has grounded $aircraftName following an automatic pressurisation system activation that prompted a precautionary descent during the $routeLabel sector. The cabin altitude alert triggered at cruise level and the crew followed the appropriate memory items, executing a controlled descent to a safe altitude.',
          'Post-flight investigation identified a faulty outflow valve controller as the initiating cause. The controller failed to regulate cabin altitude correctly under the prevailing atmospheric conditions, triggering the protective system response. The crew\'s handling of the event was assessed as exemplary by the airline\'s flight operations safety team.',
          grounds
              ? 'The aircraft has been withdrawn from service pending replacement of the outflow valve controller and a full pressurisation system functional check. The carrier has reviewed whether similar valves are approaching their service-life limit on other fleet members.'
              : 'Following replacement of the faulty controller and a successful pressurisation ground test, the aircraft was returned to the operating programme.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'landing gear fault':
      return NewsArticle(
        id: id,
        headline: '$airlineName grounds $aircraftName after landing gear indication',
        subheadline: 'Abnormal gear indication on $routeLabel departure prompts precautionary return',
        paragraphs: [
          '$airlineName has grounded $aircraftName after the crew observed an abnormal landing gear retraction indication following departure on the $routeLabel service. The crew declared a precautionary situation and elected to return to the departure aerodrome for an inspection landing, during which the gear operated normally.',
          'Engineering assessment identified a failure in the inboard main gear down-lock sensor, which was providing an intermittent indication to the cockpit display. While the fault was assessed as a sensor failure rather than a structural deficiency, the aircraft has been taken offline pending a full gear bay inspection and sensor replacement.',
          grounds
              ? 'The airline praised the crew\'s conservative decision-making in returning to base. The aircraft is expected to return to service within 24 hours once the sensor replacement and functional test are complete.'
              : 'The sensor was replaced and the gear was cycled through ten full retraction and extension cycles under ground power before the aircraft was cleared to return to service.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'fire warning':
      return NewsArticle(
        id: id,
        headline: '$airlineName $aircraftName returns to base after fire warning',
        subheadline: 'Crew actioned engine fire drill after cockpit alert on $routeLabel departure',
        paragraphs: [
          '$airlineName $aircraftName returned to its departure aerodrome after the crew received a fire warning indication in the right engine during climb-out on the $routeLabel service. The crew followed fire drill procedures, shutting down the affected engine and discharging the engine fire suppression system as a precaution before declaring an emergency and returning for an overweight landing.',
          'Post-landing inspection by fire services and airline engineers found no evidence of actual fire or heat damage in the engine bay. The warning is believed to have been initiated by a faulty fire detection loop sensor, a known intermittent failure mode on this aircraft type that triggers a spurious warning without an actual thermal event.',
          grounds
              ? 'The aircraft has been withdrawn from service pending replacement of the fire detection loop and a full engine bay inspection. The carrier commended the crew\'s exemplary adherence to procedure in responding to the warning.'
              : 'Following replacement of the detection loop and a successful engine ground run, the aircraft was returned to service. The carrier filed a mandatory occurrence report with the national authority.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'bird strike':
      return NewsArticle(
        id: id,
        headline: '$airlineName $aircraftName suffers bird strike on $routeLabel',
        subheadline: 'Avian ingestion event prompts precautionary return and engine inspection',
        paragraphs: [
          '$airlineName $aircraftName suffered a bird strike during the initial climb phase of the $routeLabel departure. The crew reported a loud impact and observed minor engine parameter fluctuations consistent with avian ingestion. The aircraft returned to the departure aerodrome as a precaution, maintaining full control throughout.',
          'Post-landing borescope inspection of both engines revealed organic debris consistent with medium-sized bird ingestion in the left engine fan section. Minor fan blade leading-edge damage was found on two blades, with no damage to the core stages. The damage is within serviceable limits under the manufacturer\'s damage tolerance criteria.',
          grounds
              ? 'The airline has elected to replace the two affected fan blades as a precautionary measure. The aerodrome operator has been notified to review wildlife strike reporting for the runway in use at the time.'
              : 'The aircraft was returned to service following the inspection. A formal bird-strike report has been submitted to the national aerodrome safety database.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    case 'tyre blowout':
      return NewsArticle(
        id: id,
        headline: '$airlineName $aircraftName reports tyre failure on $routeLabel arrival',
        subheadline: 'Main gear tyre deflation on landing causes minor delay',
        paragraphs: [
          '$airlineName $aircraftName suffered a main gear tyre deflation on landing at the end of the $routeLabel service. The tyre failed during the landing roll, resulting in a slight directional excursion corrected by the crew using differential braking. The aircraft vacated the runway normally and taxied to stand under its own power.',
          'Ground engineers inspecting the failed tyre found evidence of a sidewall cut consistent with foreign object damage sustained during the landing roll. The runway was briefly inspected by aerodrome operations and a small piece of metal debris was recovered from the landing zone.',
          'The failed tyre and its twin on the opposing bogie were replaced and the aircraft was returned to service after a brake and undercarriage functional check. The carrier filed a foreign object debris report with the aerodrome operator.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );

    default:
      return NewsArticle(
        id: id,
        headline: '$airlineName reports technical issue on $aircraftName',
        subheadline: '$faultLabel detected during $routeLabel operations',
        paragraphs: [
          '$airlineName has reported a technical defect — $faultLabel — on $aircraftName following operations on the $routeLabel sector. The fault was identified during post-flight systems monitoring and has been referred to the line maintenance team for investigation.',
          grounds
              ? 'The aircraft has been removed from the operating programme pending resolution of the defect. The airline expects the investigation to be completed within the next scheduled maintenance window.'
              : 'Engineers assessed the defect and cleared the aircraft to continue operations with an enhanced monitoring schedule and a maintenance action logged for rectification at the next available ground opportunity.',
          'The carrier reported the finding through its mandatory defect-reporting system and is cooperating with the aircraft manufacturer\'s technical support organisation to determine whether the failure mode has fleet-wide implications.',
        ],
        severity: grounds ? 'grounding' : 'news',
        gameDay: gameDay,
        suppressAutoOpen: true,
      );
  }
}
