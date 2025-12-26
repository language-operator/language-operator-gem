#!/usr/bin/env node
import { readFileSync } from "fs";
import { join } from "path";

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  permission_mode: string;
  prompt: string;
}

interface PromptTriggers {
  keywords?: string[];
  intentPatterns?: string[];
}

interface FileTriggers {
  pathPatterns?: string[];
  pathExclusions?: string[];
  contentPatterns?: string[];
}

interface SkillRule {
  type: "guardrail" | "domain";
  enforcement: "block" | "suggest" | "warn";
  priority: "critical" | "high" | "medium" | "low";
  description?: string;
  promptTriggers?: PromptTriggers;
  fileTriggers?: FileTriggers;
}

interface SkillRules {
  version: string;
  description?: string;
  skills: Record<string, SkillRule>;
}

interface MatchedSkill {
  name: string;
  matchType: "keyword" | "intent" | "file";
  config: SkillRule;
  matchDetails?: string;
}

async function main() {
  try {
    // Read input from stdin
    const input = readFileSync(0, "utf-8");
    const data: HookInput = JSON.parse(input);
    const prompt = data.prompt.toLowerCase();

    // Load skill rules
    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const rulesPath = join(projectDir, ".claude", "skills", "skill-rules.json");
    
    let rules: SkillRules;
    try {
      rules = JSON.parse(readFileSync(rulesPath, "utf-8"));
    } catch (error) {
      // If skill rules file doesn't exist, exit silently
      process.exit(0);
    }

    const matchedSkills: MatchedSkill[] = [];

    // Check each skill for matches
    for (const [skillName, config] of Object.entries(rules.skills)) {
      const triggers = config.promptTriggers;
      if (!triggers) continue;

      // Keyword matching
      if (triggers.keywords) {
        const matchedKeywords: string[] = [];
        for (const keyword of triggers.keywords) {
          if (prompt.includes(keyword.toLowerCase())) {
            matchedKeywords.push(keyword);
          }
        }
        
        if (matchedKeywords.length > 0) {
          matchedSkills.push({
            name: skillName,
            matchType: "keyword",
            config,
            matchDetails: `Keywords: ${matchedKeywords.join(", ")}`
          });
          continue;
        }
      }

      // Intent pattern matching
      if (triggers.intentPatterns) {
        for (const pattern of triggers.intentPatterns) {
          try {
            const regex = new RegExp(pattern, "i");
            if (regex.test(prompt)) {
              matchedSkills.push({
                name: skillName,
                matchType: "intent",
                config,
                matchDetails: `Pattern: ${pattern}`
              });
              break;
            }
          } catch (error) {
            // Skip invalid regex patterns
            console.error(`Invalid regex pattern: ${pattern}`, error);
          }
        }
      }
    }

    // Generate output if matches found
    if (matchedSkills.length > 0) {
      let output = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
      output += "🎯 SKILL ACTIVATION CHECK\n";
      output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n";

      // Group by priority
      const critical = matchedSkills.filter((s) => s.config.priority === "critical");
      const high = matchedSkills.filter((s) => s.config.priority === "high");
      const medium = matchedSkills.filter((s) => s.config.priority === "medium");
      const low = matchedSkills.filter((s) => s.config.priority === "low");

      if (critical.length > 0) {
        output += "⚠️  CRITICAL SKILLS (REQUIRED):\n";
        critical.forEach((s) => {
          output += `   → ${s.name}`;
          if (s.config.description) output += ` - ${s.config.description}`;
          output += "\n";
        });
        output += "\n";
      }

      if (high.length > 0) {
        output += "📚 RECOMMENDED SKILLS:\n";
        high.forEach((s) => {
          output += `   → ${s.name}`;
          if (s.config.description) output += ` - ${s.config.description}`;
          output += "\n";
        });
        output += "\n";
      }

      if (medium.length > 0) {
        output += "💡 SUGGESTED SKILLS:\n";
        medium.forEach((s) => {
          output += `   → ${s.name}`;
          if (s.config.description) output += ` - ${s.config.description}`;
          output += "\n";
        });
        output += "\n";
      }

      if (low.length > 0) {
        output += "ℹ️  OPTIONAL SKILLS:\n";
        low.forEach((s) => {
          output += `   → ${s.name}`;
          if (s.config.description) output += ` - ${s.config.description}`;
          output += "\n";
        });
        output += "\n";
      }

      // Add call to action
      if (critical.length > 0) {
        output += "⚠️  ACTION: You MUST use the critical skills before proceeding\n";
      } else if (high.length > 0) {
        output += "💡 ACTION: Consider using the Skill tool to activate relevant skills\n";
      }
      
      output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";

      process.stdout.write(output);
    }
  } catch (error) {
    // Silent fail - don't break Claude if hook fails
    // Only log to stderr for debugging, but exit successfully
    console.error("Skill activation hook error:", error);
    process.exit(0);
  }
}

main();