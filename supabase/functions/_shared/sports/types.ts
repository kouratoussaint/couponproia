// Types normalisés, indépendants du fournisseur de données sportives.

export type MatchStatus =
  | "scheduled"
  | "live"
  | "finished"
  | "postponed"
  | "cancelled"
  | "abandoned"
  | "interrupted"
  | "awarded"
  | "unknown";

export interface ProviderLeague {
  ref: string;
  name: string;
  type: "league" | "cup" | null;
  country: string | null;
  countryCode: string | null;
  logoUrl: string | null;
  currentSeason: number | null;
}

export interface ProviderTeam {
  ref: string;
  name: string;
  logoUrl: string | null;
}

export interface ProviderFixture {
  ref: string;
  leagueRef: string;
  season: number;
  round: string | null;
  kickoffAt: string;
  status: MatchStatus;
  statusShort: string;
  elapsed: number | null;
  home: ProviderTeam;
  away: ProviderTeam;
  homeGoals: number | null;
  awayGoals: number | null;
  htHomeGoals: number | null;
  htAwayGoals: number | null;
  venue: string | null;
  referee: string | null;
}

export interface ProviderStanding {
  team: ProviderTeam;
  group: string;
  rank: number;
  points: number;
  played: number;
  win: number;
  draw: number;
  lose: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDiff: number;
  form: string | null;
  description: string | null;
  home: Record<string, unknown> | null;
  away: Record<string, unknown> | null;
}

/** Une cote d'un bookmaker, déjà ramenée à un marché normalisé. */
export interface OddsQuote {
  bookmaker: string;
  market: string;
  outcome: string;
  line: number | null;
  odd: number;
}

/** Résumé d'une issue sur l'ensemble des bookmakers d'un relevé. */
export interface OddsSummary {
  market: string;
  outcome: string;
  line: number | null;
  median: number;
  best: number;
  count: number;
}

/** Contrat commun à tous les fournisseurs : changer de fournisseur = nouvel adaptateur. */
export interface SportsDataProvider {
  readonly id: string;
  /** Requêtes envoyées depuis la création de l'instance. */
  readonly requestsUsed: number;
  /** Quota journalier restant annoncé par le fournisseur, s'il le communique. */
  readonly requestsRemaining: number | null;
  getLeague(ref: string): Promise<ProviderLeague | null>;
  getFixtures(leagueRef: string, season: number): Promise<ProviderFixture[]>;
  getFixturesByIds(refs: string[]): Promise<ProviderFixture[]>;
  getStandings(leagueRef: string, season: number): Promise<ProviderStanding[]>;
  getOdds(fixtureRef: string): Promise<OddsQuote[]>;
  /** Réglages de rythme (ex. offre gratuite limitée à 10 requêtes par minute). */
  configure?(options: { minIntervalMs: number }): void;
}
